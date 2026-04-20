import Darwin
import Foundation

final class LockedTextBuffer: @unchecked Sendable {
    private var value = ""
    private let lock = NSLock()

    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        value += chunk
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
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
        var stdout = ""
        var stderr = ""

        for try await event in stream(configuration) {
            switch event {
            case .stdout(let chunk):
                stdout += chunk
            case .stderr(let chunk):
                stderr += chunk
            case .finished(let result):
                return result
            case .started:
                continue
            }
        }

        return ProcessResult(
            command: configuration.commandLine,
            stdout: stdout,
            stderr: stderr,
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
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                    return
                }
                stdoutBuffer.append(chunk)
                continuation.yield(.stdout(chunk))
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                    return
                }
                stderrBuffer.append(chunk)
                continuation.yield(.stderr(chunk))
            }

            process.terminationHandler = { [self] finishedProcess in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = ProcessResult(
                    command: configuration.commandLine,
                    stdout: stdoutBuffer.snapshot() + String(decoding: stdoutData, as: UTF8.self),
                    stderr: stderrBuffer.snapshot() + String(decoding: stderrData, as: UTF8.self),
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
