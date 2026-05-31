import Darwin
import Foundation

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

    /// Raw trailing bytes from readDataToEndOfFile() that were NOT emitted
    /// as .stdout/.stderr stream events.  Only populated in the .finished
    /// event so that run() can merge them with its own accumulation.
    var trailingStdout: Data?
    var trailingStderr: Data?

    var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: stdout.isEmpty || stderr.isEmpty ? "" : "\n")
    }

    static func == (lhs: ProcessResult, rhs: ProcessResult) -> Bool {
        lhs.command == rhs.command
            && lhs.stdout == rhs.stdout
            && lhs.stderr == rhs.stderr
            && lhs.exitCode == rhs.exitCode
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
        // Accumulate raw Data instead of String chunks so that:
        //  1. Multi-byte UTF-8 characters split across pipe reads are not
        //     corrupted with U+FFFD (the split bytes are rejoined before
        //     the single String conversion at the end).
        //  2. Trailing bytes from readDataToEndOfFile() in the .finished
        //     result are always included — previously they were lost when
        //     stdoutChunks was non-empty.
        var stdoutData = Data()
        var stderrData = Data()

        for try await event in stream(configuration) {
            switch event {
            case let .stdout(chunk):
                stdoutData.append(contentsOf: chunk.utf8)
            case let .stderr(chunk):
                stderrData.append(contentsOf: chunk.utf8)
            case let .finished(result):
                // Prefer our unlimited accumulation over the capacity-limited
                // LockedTextBuffer snapshot (large probe payloads >16 MB are
                // silently truncated by the buffer's eviction policy).
                // Append any trailing bytes from readDataToEndOfFile() that
                // were not emitted as .stdout/.stderr events.
                if let trailingStdout = result.trailingStdout {
                    stdoutData.append(trailingStdout)
                }
                if let trailingStderr = result.trailingStderr {
                    stderrData.append(trailingStderr)
                }
                return ProcessResult(
                    command: result.command,
                    stdout: stdoutData.isEmpty ? result.stdout : String(decoding: stdoutData, as: UTF8.self),
                    stderr: stderrData.isEmpty ? result.stderr : String(decoding: stderrData, as: UTF8.self),
                    exitCode: result.exitCode
                )
            case .started:
                continue
            }
        }

        return ProcessResult(
            command: configuration.commandLine,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
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
                // Use String(decoding:as:) to avoid dropping entire chunks when a
                // multi-byte UTF-8 character is split across pipe read boundaries.
                let chunk = String(decoding: data, as: UTF8.self)
                stdoutBuffer.append(chunk)
                continuation.yield(.stdout(chunk))
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(decoding: data, as: UTF8.self)
                stderrBuffer.append(chunk)
                continuation.yield(.stderr(chunk))
            }

            process.terminationHandler = { [self] finishedProcess in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let trailingStdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let trailingStderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = ProcessResult(
                    command: configuration.commandLine,
                    stdout: stdoutBuffer.snapshot() + String(decoding: trailingStdoutData, as: UTF8.self),
                    stderr: stderrBuffer.snapshot() + String(decoding: trailingStderrData, as: UTF8.self),
                    exitCode: finishedProcess.terminationStatus,
                    trailingStdout: trailingStdoutData.isEmpty ? nil : trailingStdoutData,
                    trailingStderr: trailingStderrData.isEmpty ? nil : trailingStderrData
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
