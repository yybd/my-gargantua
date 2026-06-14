import Foundation
import OSLog

private let codexScheduledHookLogger = Logger(subsystem: "com.gargantua.core", category: "CodexScheduledAgentAuditHook")

/// Runs a one-shot read-only Codex audit after scheduled scans when enabled.
/// The Codex sibling of `ClaudeCodeScheduledAgentAuditHook`: where Claude
/// drives an interactive MCP session, Codex fires a single `codex exec`
/// read-only run over the scan summary and discards the transcript (the value
/// is the unattended run itself; failures are logged).
public struct CodexScheduledAgentAuditHook: ScheduledScanAgentAuditHook {
    private let configurationStore: CodexAgentConfigurationStore
    private let cliResolver: CodexCLIResolver
    private let runner: CodexOneShotRunner

    /// Creates an audit hook with optional dependency injection.
    public init(
        configurationStore: CodexAgentConfigurationStore = CodexAgentConfigurationStore(),
        cliResolver: CodexCLIResolver = CodexCLIResolver(),
        runner: CodexOneShotRunner = CodexOneShotRunner()
    ) {
        self.configurationStore = configurationStore
        self.cliResolver = cliResolver
        self.runner = runner
    }

    /// Runs the scheduled-scan audit prompt when the Codex integration is
    /// enabled and opted into scheduled runs.
    public func run(summary: ScheduledScanSummary) async {
        let configuration = configurationStore.load()
        guard configuration.isEnabled, configuration.runAfterScheduledScans else { return }

        let executable: URL
        do {
            executable = try cliResolver.resolve(configuration: configuration)
        } catch {
            codexScheduledHookLogger.warning("Scheduled Codex audit hook skipped: \(error.localizedDescription)")
            return
        }

        let prompt = CodexAgentPromptBuilder.scheduledAuditPrompt(summary: summary)
        do {
            _ = try await runner.run(
                executable: executable,
                prompt: prompt,
                model: configuration.selectedModel
            )
        } catch {
            codexScheduledHookLogger.warning("Scheduled Codex audit hook failed: \(error.localizedDescription)")
        }
    }
}

/// Dispatches scheduled-scan audits to whichever engine is assigned to the
/// `maintenance` job, re-read on every run so changing the assignment in
/// Settings takes effect without rebuilding the scheduler. Claude Code is the
/// default; Codex is selected when the user assigns `.codex` to maintenance.
// `@unchecked Sendable`: the only stored non-Sendable member is `UserDefaults`,
// which Apple documents as thread-safe; the hooks are `Sendable` already.
public struct MaintenanceEngineAuditHook: ScheduledScanAgentAuditHook, @unchecked Sendable {
    private let defaults: UserDefaults
    private let claudeHook: any ScheduledScanAgentAuditHook
    private let codexHook: any ScheduledScanAgentAuditHook

    /// Creates the dispatcher with optional per-engine hook injection.
    public init(
        defaults: UserDefaults = .standard,
        claudeHook: any ScheduledScanAgentAuditHook = ClaudeCodeScheduledAgentAuditHook(),
        codexHook: any ScheduledScanAgentAuditHook = CodexScheduledAgentAuditHook()
    ) {
        self.defaults = defaults
        self.claudeHook = claudeHook
        self.codexHook = codexHook
    }

    /// Reads the current maintenance-engine assignment and forwards to it.
    public func run(summary: ScheduledScanSummary) async {
        switch AIEngineAssignments.engine(for: .maintenance, in: defaults) {
        case .codex:
            await codexHook.run(summary: summary)
        default:
            await claudeHook.run(summary: summary)
        }
    }
}
