import Foundation
import OSLog

private let codexOneShotLogger = Logger(
    subsystem: "com.gargantua.core",
    category: "CodexOneShotRunner"
)

/// Runs the user's `codex` CLI as a single read-only completion:
/// `codex exec --skip-git-repo-check --sandbox read-only -o <file> [--model m]
/// "<prompt>"`. Codex writes only the assistant's final message to the `-o`
/// file, which this returns; the read-only sandbox blocks writes and actions.
///
/// Shared by every one-shot Codex consumer (file-organization proposals,
/// deeper explanations) so the subprocess plumbing lives in one place.
public struct CodexOneShotRunner: @unchecked Sendable {
    private let processFactory: @Sendable () -> Process
    private let fileManager: FileManager
    private let timeoutSeconds: Int

    public init(
        processFactory: @Sendable @escaping () -> Process = { Process() },
        fileManager: FileManager = .default,
        timeoutSeconds: Int = 240
    ) {
        self.processFactory = processFactory
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
    }

    public func run(executable: URL, prompt: String, model: String) async throws -> String {
        let lastMessageFile = fileManager.temporaryDirectory
            .appendingPathComponent("gargantua-codex-out-\(UUID().uuidString).txt")
        defer { try? fileManager.removeItem(at: lastMessageFile) }

        var arguments = [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "-o", lastMessageFile.path,
        ]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            arguments += ["--model", trimmedModel]
        }
        arguments.append(prompt)

        codexOneShotLogger.error(
            "codex one-shot start: \(executable.path, privacy: .public) prompt-len=\(prompt.count) model=\(trimmedModel, privacy: .public)"
        )

        let processBox = CodexProcessBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let process = processFactory()
                processBox.process = process
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdoutBuffer = CodexDataBuffer()
                let stderrBuffer = CodexDataBuffer()
                let resumed = CodexAtomicFlag()

                let pipes = CodexSubprocessPipes(stdout: stdoutPipe, stderr: stderrPipe)
                let buffers = CodexSubprocessBuffers(stdout: stdoutBuffer, stderr: stderrBuffer)
                configure(process: process, executable: executable, arguments: arguments, pipes: pipes)
                attachReadabilityHandlers(pipes: pipes, buffers: buffers)
                process.terminationHandler = makeTerminationHandler(
                    pipes: pipes,
                    buffers: buffers,
                    resumed: resumed,
                    continuation: continuation
                )
                spawnTimeoutWatcher(process: process, resumed: resumed, continuation: continuation)

                do {
                    try process.run()
                } catch {
                    if resumed.takeIfFalse() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.process?.terminate()
        }

        guard let data = try? Data(contentsOf: lastMessageFile),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexOneShotError.emptyResponse
        }
        return text
    }

    // MARK: - Subprocess helpers

    private func configure(process: Process, executable: URL, arguments: [String], pipes: CodexSubprocessPipes) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipes.stdout
        process.standardError = pipes.stderr
    }

    private func attachReadabilityHandlers(pipes: CodexSubprocessPipes, buffers: CodexSubprocessBuffers) {
        pipes.stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffers.stdout.append(chunk)
            }
        }
        pipes.stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffers.stderr.append(chunk)
            }
        }
    }

    private func makeTerminationHandler(
        pipes: CodexSubprocessPipes,
        buffers: CodexSubprocessBuffers,
        resumed: CodexAtomicFlag,
        continuation: CheckedContinuation<Void, Error>
    ) -> @Sendable (Process) -> Void {
        return { proc in
            pipes.stdout.fileHandleForReading.readabilityHandler = nil
            pipes.stderr.fileHandleForReading.readabilityHandler = nil
            if let remaining = try? pipes.stdout.fileHandleForReading.readToEnd() {
                buffers.stdout.append(remaining)
            }
            if let remaining = try? pipes.stderr.fileHandleForReading.readToEnd() {
                buffers.stderr.append(remaining)
            }
            guard resumed.takeIfFalse() else { return }
            let status = proc.terminationStatus
            let stderrString = String(data: buffers.stderr.snapshot(), encoding: .utf8) ?? ""
            codexOneShotLogger.error(
                "codex one-shot exit: status=\(status) stderr-bytes=\(stderrString.count)"
            )
            if status == 0, proc.terminationReason == .exit {
                continuation.resume(returning: ())
            } else {
                codexOneShotLogger.error("codex CLI stderr: \(stderrString.prefix(600), privacy: .public)")
                continuation.resume(throwing: CodexOneShotError.cliFailed(
                    exitCode: Int(status),
                    stderr: stderrString
                ))
            }
        }
    }

    private func spawnTimeoutWatcher(
        process: Process,
        resumed: CodexAtomicFlag,
        continuation: CheckedContinuation<Void, Error>
    ) {
        let seconds = timeoutSeconds
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            if process.isRunning, resumed.takeIfFalse() {
                codexOneShotLogger.error("codex CLI timed out after \(seconds)s — terminating subprocess")
                process.terminate()
                continuation.resume(throwing: CodexOneShotError.timedOut(seconds: seconds))
            }
        }
    }
}

/// Failure modes of a one-shot `codex` invocation. Callers map these onto
/// their own feature-specific error types for user-facing messages.
public enum CodexOneShotError: Error, Equatable {
    case cliFailed(exitCode: Int, stderr: String)
    case emptyResponse
    case timedOut(seconds: Int)
}

private final class CodexProcessBox: @unchecked Sendable {
    var process: Process?
}

private struct CodexSubprocessPipes {
    let stdout: Pipe
    let stderr: Pipe
}

private struct CodexSubprocessBuffers {
    let stdout: CodexDataBuffer
    let stderr: CodexDataBuffer
}

private final class CodexAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flipped = false

    func takeIfFalse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flipped { return false }
        flipped = true
        return true
    }
}

private final class CodexDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
