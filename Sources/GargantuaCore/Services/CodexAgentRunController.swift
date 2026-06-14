import Foundation
import OSLog

private let codexAgentRunLogger = Logger(subsystem: "com.gargantua.core", category: "CodexAgentRunController")

/// Phase of a one-shot Codex agent run.
public enum CodexAgentRunStatus: Equatable, Sendable {
    case idle
    case running
    case finished
    case failed

    public var isRunning: Bool { self == .running }
}

/// Drives a single read-only `codex exec` agent run from the Agent Run screen.
/// Far simpler than `ClaudeCodeAgentSessionController`: Codex is one-shot with
/// no MCP, no approval gates, and no streaming — the controller resolves the
/// CLI, builds the prompt, runs it, and publishes the returned report.
@MainActor
public final class CodexAgentRunController: ObservableObject {
    @Published public private(set) var status: CodexAgentRunStatus = .idle
    /// The assistant's returned report once a run finishes.
    @Published public private(set) var output: String = ""
    /// User-facing error message when a run fails.
    @Published public private(set) var errorMessage: String?

    private let configurationStore: CodexAgentConfigurationStore
    private let cliResolver: CodexCLIResolver
    private let runner: CodexOneShotRunner

    private var lastTemplate: CodexAgentPromptTemplate = .investigateSpace
    private var lastUserContext: String = ""
    private var runTask: Task<Void, Never>?
    /// Identifies the in-flight run so a cancelled/superseded task can't stamp
    /// its outcome onto a newer run. Bumped on every start and on cancel.
    private var activeRunToken = 0

    public init(
        configurationStore: CodexAgentConfigurationStore = CodexAgentConfigurationStore(),
        cliResolver: CodexCLIResolver = CodexCLIResolver(),
        runner: CodexOneShotRunner = CodexOneShotRunner()
    ) {
        self.configurationStore = configurationStore
        self.cliResolver = cliResolver
        self.runner = runner
    }

    deinit {
        // Tear down the `codex exec` subprocess if the screen goes away mid-run;
        // the runner terminates the process on cancellation.
        runTask?.cancel()
    }

    /// Starts a run for the given template and user context. No-op while a run
    /// is already in flight.
    public func start(template: CodexAgentPromptTemplate, userContext: String) {
        guard !status.isRunning else { return }
        lastTemplate = template
        lastUserContext = userContext
        output = ""
        errorMessage = nil
        status = .running
        activeRunToken &+= 1
        let token = activeRunToken

        let configuration = configurationStore.load()
        guard configuration.isEnabled else {
            fail(with: CodexExplainError.agentNotEnabled, token: token)
            return
        }

        let executable: URL
        do {
            executable = try cliResolver.resolve(configuration: configuration)
        } catch {
            fail(with: error, token: token)
            return
        }

        let prompt = CodexAgentPromptBuilder.prompt(template: template, userContext: userContext)
        let model = configuration.selectedModel
        let runner = runner
        runTask = Task { [weak self] in
            do {
                let text = try await runner.run(executable: executable, prompt: prompt, model: model)
                await self?.finish(with: text.trimmingCharacters(in: .whitespacesAndNewlines), token: token)
            } catch let error as CodexOneShotError {
                await self?.fail(with: CodexExplainError(oneShot: error), token: token)
            } catch {
                await self?.fail(with: error, token: token)
            }
        }
    }

    /// Re-runs the most recent template + context.
    public func restart() {
        guard !status.isRunning else { return }
        start(template: lastTemplate, userContext: lastUserContext)
    }

    /// Cancels an in-flight run, returning to idle. Bumping the token means the
    /// cancelled task's eventual outcome is ignored (cancellation can surface
    /// as a `cliFailed`, not a `CancellationError`).
    public func cancel() {
        activeRunToken &+= 1
        runTask?.cancel()
        runTask = nil
        if status.isRunning {
            status = .idle
        }
    }

    private func finish(with text: String, token: Int) {
        guard token == activeRunToken else { return }
        output = text
        errorMessage = nil
        status = .finished
        runTask = nil
    }

    private func fail(with error: Error, token: Int) {
        guard token == activeRunToken else { return }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        codexAgentRunLogger.warning("Codex agent run failed: \(message, privacy: .private)")
        errorMessage = message
        status = .failed
        runTask = nil
    }
}
