import Darwin
import Foundation

/// Buffers raw bytes and decodes complete UTF-8 sequences only,
/// carrying incomplete trailing bytes across pipe reads.
///
/// When a multi-byte character (e.g. CJK, emoji) is split across two
/// `availableData` calls, naively decoding each chunk replaces the
/// split bytes with U+FFFD.  This class accumulates the incomplete
/// tail and prepends it to the next read so the full character is
/// decoded correctly.
final class UTF8LineBuffer: @unchecked Sendable {
    private var remainder = Data()
    private let lock = NSLock()

    /// Decode as much valid UTF-8 as possible from `data`, carrying
    /// any incomplete trailing sequence for the next call.
    /// Returns the decoded string (may be empty if only a partial
    /// sequence was received).
    func decode(_ data: Data) -> String {
        lock.lock()
        defer { lock.unlock() }

        var combined = remainder + data
        remainder = Data()

        // Find how many trailing bytes form an incomplete UTF-8 sequence.
        let incomplete = incompleteTrailingBytes(combined)
        if incomplete > 0 {
            remainder = combined.suffix(incomplete)
            combined = combined.dropLast(incomplete)
        }

        guard !combined.isEmpty else { return "" }
        return String(decoding: combined, as: UTF8.self)
    }

    /// Flush any buffered remainder, decoding whatever is left
    /// (possibly with replacement characters for truly broken data).
    func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !remainder.isEmpty else { return "" }
        let result = String(decoding: remainder, as: UTF8.self)
        remainder = Data()
        return result
    }

    /// Returns the number of trailing bytes that form an incomplete
    /// multi-byte UTF-8 sequence, or 0 if the data ends cleanly.
    private func incompleteTrailingBytes(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }

        // Walk backwards (up to 3 bytes — max continuation run for a
        // 4-byte sequence) looking for a leading byte whose expected
        // sequence length exceeds the bytes available after it.
        let count = data.count
        let start = data.startIndex
        let scanLimit = min(count, 4)

        for i in 1...scanLimit {
            let byteIndex = start + count - i
            let byte = data[byteIndex]

            if byte & 0x80 == 0 {
                // ASCII — everything before this is complete.
                return 0
            }

            if byte & 0xC0 == 0xC0 {
                // This is a leading byte.  Determine expected length.
                let expected: Int
                if byte & 0xE0 == 0xC0 { expected = 2 }
                else if byte & 0xF0 == 0xE0 { expected = 3 }
                else if byte & 0xF8 == 0xF0 { expected = 4 }
                else { return 0 } // Invalid leading byte — let decoder handle it.

                let available = i
                return available < expected ? available : 0
            }

            // 0x80..0xBF — continuation byte, keep scanning backwards.
        }

        // All scanned bytes are continuation bytes with no leader found
        // within 4 bytes — malformed; let decoder handle it.
        return 0
    }
}

/// Thread-safe text buffer with a configurable byte capacity.
///
/// When the accumulated content exceeds `capacity`, the oldest chunks
/// are evicted so that only the most recent output survives.  This
/// prevents unbounded memory growth during long-running downloads.
final class LockedTextBuffer: @unchecked Sendable {
    private var chunks: [String] = []
    private var headIndex = 0
    private var totalBytes = 0
    private let capacity: Int
    private let lock = NSLock()

    /// - Parameter capacity: Maximum retained bytes (UTF-8).  Defaults to 16 MB.
    init(capacity: Int = 16 * 1_048_576) {
        self.capacity = capacity
    }

    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        let chunkBytes = chunk.utf8.count
        totalBytes += chunkBytes
        chunks.append(chunk)
        while totalBytes > capacity, headIndex < chunks.count {
            totalBytes -= chunks[headIndex].utf8.count
            chunks[headIndex] = "" // release string memory
            headIndex += 1
        }
        // Compact the array when more than half is dead entries.
        if headIndex > 64, headIndex > chunks.count / 2 {
            chunks.removeFirst(headIndex)
            headIndex = 0
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks[headIndex...].joined()
    }
}

struct ProcessResult: Equatable {
    var command: [String]
    var stdout: String
    var stderr: String
    var exitCode: Int32

    var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: stdout.isEmpty || stderr.isEmpty ? "" : "\n")
    }
}

enum ProcessEvent: Equatable {
    case started(pid: Int32)
    case stdout(String)
    case stderr(String)
    case finished(ProcessResult)
}

struct ProcessConfiguration {
    var executableURL: URL
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var currentDirectoryURL: URL?
    var terminationGracePeriod: Duration = .seconds(2)

    var commandLine: [String] {
        [executableURL.path] + arguments
    }
}

final class ProcessRunner: @unchecked Sendable {
    private var activeProcess: Process?
    private let lock = NSLock()

    func run(_ configuration: ProcessConfiguration) async throws -> ProcessResult {
        // Accumulate chunks from stream events.  UTF-8 correctness is
        // handled by UTF8LineBuffer inside stream(), so chunks here are
        // already valid strings.  We still accumulate our own copy to
        // avoid the 16 MB cap of LockedTextBuffer on large probe output.
        var stdoutChunks: [String] = []
        var stderrChunks: [String] = []

        for try await event in stream(configuration) {
            switch event {
            case let .stdout(chunk):
                stdoutChunks.append(chunk)
            case let .stderr(chunk):
                stderrChunks.append(chunk)
            case let .finished(result):
                // Prefer our unlimited accumulation over the capacity-limited
                // LockedTextBuffer snapshot in result.stdout/stderr.
                return ProcessResult(
                    command: result.command,
                    stdout: stdoutChunks.isEmpty ? result.stdout : stdoutChunks.joined(),
                    stderr: stderrChunks.isEmpty ? result.stderr : stderrChunks.joined(),
                    exitCode: result.exitCode
                )
            case .started:
                continue
            }
        }

        return ProcessResult(
            command: configuration.commandLine,
            stdout: stdoutChunks.joined(),
            stderr: stderrChunks.joined(),
            exitCode: 0
        )
    }

    func stream(_ configuration: ProcessConfiguration) -> AsyncThrowingStream<ProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdoutBuffer = LockedTextBuffer()
            let stderrBuffer = LockedTextBuffer()
            let stdoutDecoder = UTF8LineBuffer()
            let stderrDecoder = UTF8LineBuffer()

            process.executableURL = configuration.executableURL
            process.arguments = configuration.arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.currentDirectoryURL = configuration.currentDirectoryURL
            if !configuration.environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, new in new }
            }

            configureProcessGroup(process)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = stdoutDecoder.decode(data)
                guard !chunk.isEmpty else { return }
                stdoutBuffer.append(chunk)
                continuation.yield(.stdout(chunk))
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = stderrDecoder.decode(data)
                guard !chunk.isEmpty else { return }
                stderrBuffer.append(chunk)
                continuation.yield(.stderr(chunk))
            }

            process.terminationHandler = { [self] finishedProcess in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // Drain any remaining pipe data.
                let trailingStdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let trailingStderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                // Decode trailing pipe data + flush any incomplete UTF-8
                // remainder, and yield as normal stream events so ALL
                // callers (both run() and direct stream() consumers) see
                // the complete output.
                let trailingStdout = stdoutDecoder.decode(trailingStdoutData) + stdoutDecoder.flush()
                if !trailingStdout.isEmpty {
                    stdoutBuffer.append(trailingStdout)
                    continuation.yield(.stdout(trailingStdout))
                }

                let trailingStderr = stderrDecoder.decode(trailingStderrData) + stderrDecoder.flush()
                if !trailingStderr.isEmpty {
                    stderrBuffer.append(trailingStderr)
                    continuation.yield(.stderr(trailingStderr))
                }

                let result = ProcessResult(
                    command: configuration.commandLine,
                    stdout: stdoutBuffer.snapshot(),
                    stderr: stderrBuffer.snapshot(),
                    exitCode: finishedProcess.terminationStatus
                )

                clearActiveProcess()
                continuation.yield(.finished(result))
                continuation.finish()
            }

            do {
                try process.run()
                // Move child into its own process group so killpg can cover
                // the full yt-dlp → ffmpeg subtree on cancel.
                // Race window is small; yt-dlp forks ffmpeg well after startup.
                setpgid(process.processIdentifier, process.processIdentifier)
                storeActiveProcess(process)
                continuation.yield(.started(pid: process.processIdentifier))
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: error)
            }

            continuation.onTermination = { [self] _ in
                Task {
                    try? await cancel(gracePeriod: configuration.terminationGracePeriod)
                }
            }
        }
    }

    func cancel(gracePeriod: Duration = .seconds(2)) async throws {
        guard let process = currentActiveProcess() else {
            return
        }

        let pid = process.processIdentifier
        // Send SIGTERM to the entire process group (covers yt-dlp → ffmpeg subtree).
        // Falls back to direct kill in case pgid wiring raced.
        killpg(pid, SIGTERM)
        process.terminate()

        // Duration.components.seconds truncates sub-second values, so we must
        // also fold in the attoseconds portion (1 ns = 1_000_000_000 as).
        let comps = gracePeriod.components
        let graceNanoseconds = UInt64(max(comps.seconds, 0)) * 1_000_000_000
            + UInt64(max(comps.attoseconds, 0)) / 1_000_000_000
        if graceNanoseconds > 0 {
            try await Task.sleep(nanoseconds: graceNanoseconds)
        }

        if process.isRunning {
            killpg(pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    private func configureProcessGroup(_ process: Process) {
        process.qualityOfService = .userInitiated
    }

    private func storeActiveProcess(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        activeProcess = process
    }

    private func currentActiveProcess() -> Process? {
        lock.lock()
        defer { lock.unlock() }
        return activeProcess
    }

    private func clearActiveProcess() {
        lock.lock()
        defer { lock.unlock() }
        activeProcess = nil
    }
}
