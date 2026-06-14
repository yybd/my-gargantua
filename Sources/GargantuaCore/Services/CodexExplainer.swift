import Foundation

/// Explanation routed through the user's local `codex` CLI (their Codex
/// subscription/auth), for the explanation jobs that allow Codex. Reuses the
/// Codex agent's configured CLI path + model, builds the same prose
/// explanation prompt the other providers use, and runs it one-shot read-only.
public struct CodexExplainer: Sendable {
    private let configurationStore: CodexAgentConfigurationStore
    private let cliResolver: CodexCLIResolver
    private let runner: CodexOneShotRunner

    public init(
        configurationStore: CodexAgentConfigurationStore = CodexAgentConfigurationStore(),
        cliResolver: CodexCLIResolver = CodexCLIResolver(),
        runner: CodexOneShotRunner = CodexOneShotRunner()
    ) {
        self.configurationStore = configurationStore
        self.cliResolver = cliResolver
        self.runner = runner
    }

    public func explain(result: ScanResult, rule _: ScanRule) async throws -> AIExplanation {
        let configuration = configurationStore.load()
        guard configuration.isEnabled else {
            throw CodexExplainError.agentNotEnabled
        }
        let executable = try cliResolver.resolve(configuration: configuration)

        let items = try CloudAIRedactor.items(from: [result], allowsFileContents: false)
        guard let item = items.first else {
            throw CodexExplainError.agentNotEnabled
        }
        let prompt = try CloudAIPromptBuilder.explanationPrompt(item: item)

        let text: String
        do {
            text = try await runner.run(
                executable: executable,
                prompt: prompt,
                model: configuration.selectedModel
            )
        } catch let error as CodexOneShotError {
            throw CodexExplainError(oneShot: error)
        }

        return AIExplanation(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .codex
        )
    }

    /// Whether the Codex provider can run an explanation right now: the agent
    /// is enabled and its CLI resolves.
    public func canExplain() -> Bool {
        let configuration = configurationStore.load()
        guard configuration.isEnabled else { return false }
        return (try? cliResolver.resolve(configuration: configuration)) != nil
    }
}

public enum CodexExplainError: Error, LocalizedError, Equatable {
    case agentNotEnabled
    case cliFailed(exitCode: Int, stderr: String)
    case emptyResponse
    case timedOut(seconds: Int)

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
        case .agentNotEnabled:
            return "Codex agent is not enabled. Turn it on in Settings → AI → Codex."
        case .cliFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "codex CLI exited with status \(exitCode)."
            }
            return "codex CLI failed: \(trimmed)"
        case .emptyResponse:
            return "codex CLI returned no output. Check that you're logged in (`codex login`)."
        case .timedOut(let seconds):
            return "codex CLI didn't respond within \(seconds)s. Try Cloud or Claude Code."
        }
    }
}
