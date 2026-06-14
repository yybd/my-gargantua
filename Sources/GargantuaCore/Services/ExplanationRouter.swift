import Foundation

/// Routes an explanation request to whichever engine is assigned to the job
/// (`AIEngineAssignments`). Both the inline "Why?" and the on-demand "Explain
/// deeper" actions flow through here — they differ only in which `AIUseCase`
/// they pass, so a user can point inline at the local model and deeper at the
/// Cloud, or any other combination the matrix allows.
@MainActor
public final class ExplanationRouter {
    private let local: any AIServiceProtocol
    private let cloud: CloudAIService
    private let claudeCode: ClaudeCodeDeeperExplainer
    private let codex: CodexExplainer
    private let assignment: (AIUseCase) -> AIEngineID

    public init(
        local: any AIServiceProtocol,
        cloud: CloudAIService,
        claudeCode: ClaudeCodeDeeperExplainer = ClaudeCodeDeeperExplainer(),
        codex: CodexExplainer = CodexExplainer(),
        assignment: @escaping (AIUseCase) -> AIEngineID = { AIEngineAssignments.engine(for: $0) }
    ) {
        self.local = local
        self.cloud = cloud
        self.claudeCode = claudeCode
        self.codex = codex
        self.assignment = assignment
    }

    public func explain(_ useCase: AIUseCase, result: ScanResult, rule: ScanRule) async throws -> AIExplanation {
        switch assignment(useCase) {
        case .template, .mlx:
            // LocalAIService is kept in sync with the chosen local engine via
            // AIEngineAssignments, so this runs Template or MLX accordingly.
            return try await local.explain(result: result, rule: rule)
        case .cloud:
            return try await cloud.explain(result: result, rule: rule)
        case .claudeCode:
            return try await claudeCode.explain(result: result, rule: rule)
        case .codex:
            return try await codex.explain(result: result, rule: rule)
        }
    }

    /// Whether the engine assigned to `useCase` is configured and ready.
    public func isAvailable(_ useCase: AIUseCase) -> Bool {
        switch assignment(useCase) {
        case .template, .mlx:
            return true
        case .cloud:
            return cloud.canExplainDeeper()
        case .claudeCode:
            return claudeCode.canExplainDeeper()
        case .codex:
            return codex.canExplain()
        }
    }
}
