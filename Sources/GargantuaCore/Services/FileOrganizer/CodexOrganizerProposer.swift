import Foundation

/// File-organization proposer routed through the user's `codex` CLI via the
/// shared `CodexOneShotRunner` (`codex exec` one-shot). Mirrors the Claude Code
/// path: same cluster prompt, response schema, and reassembly + validate()
/// pipeline.
public struct CodexOrganizerProposer: @unchecked Sendable {
    private let configurationStore: CodexAgentConfigurationStore
    private let cliResolver: CodexCLIResolver
    private let processFactory: @Sendable () -> Process
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let timeoutSeconds: Int

    public init(
        configurationStore: CodexAgentConfigurationStore = CodexAgentConfigurationStore(),
        cliResolver: CodexCLIResolver = CodexCLIResolver(),
        processFactory: @Sendable @escaping () -> Process = { Process() },
        now: @Sendable @escaping () -> Date = { Date() },
        fileManager: FileManager = .default,
        timeoutSeconds: Int = 240
    ) {
        self.configurationStore = configurationStore
        self.cliResolver = cliResolver
        self.processFactory = processFactory
        self.now = now
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
    }

    public func propose(sourceFolder: URL) async throws -> OrganizationProposal {
        let configuration = configurationStore.load()
        guard configuration.isEnabled else {
            throw CodexAgentError.disabled
        }
        let executable = try cliResolver.resolve(configuration: configuration)

        let listing = try CloudOrganizerProposer.listFolder(at: sourceFolder, fileManager: fileManager)
        let clusters = OrganizerClusterer.cluster(listing)
        let prompt = CloudOrganizerProposer.buildPrompt(
            folderName: sourceFolder.lastPathComponent,
            clusters: clusters
        )

        let runner = CodexOneShotRunner(
            processFactory: processFactory,
            fileManager: fileManager,
            timeoutSeconds: timeoutSeconds
        )
        let output: String
        do {
            output = try await runner.run(
                executable: executable,
                prompt: prompt,
                model: configuration.selectedModel
            )
        } catch let error as CodexOneShotError {
            throw CodexOrganizerError(oneShot: error)
        }

        return try CloudOrganizerProposer.parseResponse(
            text: output,
            sourceFolder: sourceFolder,
            clusters: clusters,
            backend: .cloud,
            generatedAt: now()
        )
    }
}

public enum CodexOrganizerError: Error, LocalizedError, Equatable {
    case cliFailed(exitCode: Int, stderr: String)
    case emptyResponse
    case timedOut(seconds: Int)

    /// Map a shared one-shot runner failure onto the organizer's own error
    /// surface so callers and tests keep seeing organizer-specific cases.
    init(oneShot: CodexOneShotError) {
        switch oneShot {
        case .cliFailed(let exitCode, let stderr):
            self = .cliFailed(exitCode: exitCode, stderr: stderr)
        case .emptyResponse:
            self = .emptyResponse
        case .timedOut(let seconds):
            self = .timedOut(seconds: seconds)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .cliFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "codex CLI exited with status \(exitCode)."
            }
            return "codex CLI failed: \(trimmed)"
        case .emptyResponse:
            return "codex CLI returned no output. Check that you're logged in (`codex login`)."
        case .timedOut(let seconds):
            return "codex CLI didn't respond within \(seconds)s. Try Cloud, Claude Code, or On-device rules."
        }
    }
}
