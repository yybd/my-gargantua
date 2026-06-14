import Foundation

/// The five AI engines a user can configure once and then assign to jobs.
/// Distinct from `AIEnginePreference` (which is only the local Template-vs-MLX
/// choice): this is the full roster the assignment matrix routes across.
public enum AIEngineID: String, CaseIterable, Codable, Identifiable, Sendable {
    case template
    case mlx
    case cloud
    case claudeCode
    case codex

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .template: "Template"
        case .mlx: "Local MLX"
        case .cloud: "Cloud (Anthropic)"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var systemImage: String {
        switch self {
        case .template: "doc.text"
        case .mlx: "cpu"
        case .cloud: "cloud"
        case .claudeCode: "terminal"
        case .codex: "terminal"
        }
    }

    /// Whether this engine runs entirely on-device (no network, no per-call cost).
    public var isLocal: Bool {
        self == .template || self == .mlx
    }
}

/// The jobs an engine can be assigned to. Each has its own persisted
/// assignment and its own set of engines that can actually serve it.
public enum AIUseCase: String, CaseIterable, Identifiable, Sendable {
    /// The instant per-row "Why?" explanation.
    case inlineExplain
    /// The on-demand "Explain deeper" escalation.
    case deeperExplain
    /// File Organizer proposals.
    case organize
    /// Agentic maintenance runs (scheduled audits, agent runs).
    case maintenance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inlineExplain: "Inline “Why?”"
        case .deeperExplain: "Explain deeper"
        case .organize: "Organize files"
        case .maintenance: "Run maintenance"
        }
    }

    public var subtitle: String {
        switch self {
        case .inlineExplain: "The quick answer when you tap “Why?” on a scan row."
        case .deeperExplain: "The richer write-up when you tap “Explain deeper”."
        case .organize: "How the File Organizer proposes folder structures."
        case .maintenance: "The agent that runs scheduled audits and agent runs."
        }
    }

    /// Default engine when nothing is stored. Mirrors prior behavior:
    /// inline/organize were local, deeper was Cloud, maintenance was Claude Code.
    public var defaultEngine: AIEngineID {
        switch self {
        case .inlineExplain: .template
        case .deeperExplain: .cloud
        case .organize: .template
        case .maintenance: .claudeCode
        }
    }

    /// Engines that can actually perform this job. Order is the display order.
    public var supportedEngines: [AIEngineID] {
        switch self {
        case .inlineExplain, .organize:
            return AIEngineID.allCases
        case .deeperExplain:
            return [.cloud, .claudeCode, .codex]
        case .maintenance:
            // Claude Code drives the interactive MCP agent; Codex runs a
            // one-shot read-only `codex exec` audit. Both can serve maintenance.
            return [.claudeCode, .codex]
        }
    }

    public func canUse(_ engine: AIEngineID) -> Bool {
        supportedEngines.contains(engine)
    }

    /// Why `engine` can't serve this job — shown on the greyed-out option.
    /// Returns nil when the engine is valid for the job.
    public func disabledReason(for engine: AIEngineID) -> String? {
        guard !canUse(engine) else { return nil }
        switch self {
        case .deeperExplain where engine.isLocal:
            return "On-device models aren’t strong enough for a deeper write-up."
        case .maintenance where engine.isLocal:
            return "On-device engines can’t run agentic tasks."
        case .maintenance where engine == .cloud:
            return "The hosted API answers prompts but can’t run tools or take actions."
        default:
            return "Not available for this job."
        }
    }
}
