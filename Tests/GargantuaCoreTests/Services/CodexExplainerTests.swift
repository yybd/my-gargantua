import Foundation
import Testing
@testable import GargantuaCore

/// Drives `CodexExplainer` through a fake `codex` CLI. Codex writes its reply
/// to the `-o <file>` last-message file, so the happy-path script parses its
/// own args and writes there.
@Suite("CodexExplainer")
struct CodexExplainerTests {
    private func makeResult() -> ScanResult {
        ScanResult(
            id: "explain-me",
            name: "Chrome Cache",
            path: "/tmp/cache",
            size: 2048,
            safety: .safe,
            confidence: 95,
            explanation: "Regenerated on launch.",
            source: SourceAttribution(name: "Chrome", bundleID: "com.google.Chrome"),
            category: "browser_cache",
            tags: ["browser"],
            regenerates: true
        )
    }

    private func writeToOutputFileScript(text: String) -> String {
        """
        out=""
        prev=""
        for a in "$@"; do
          if [ "$prev" = "-o" ]; then out="$a"; fi
          prev="$a"
        done
        printf '%s' '\(text)' > "$out"
        """
    }

    private func makeExplainer(enabled: Bool, cliBody: String = "") throws -> CodexExplainer {
        let store = CodexAgentConfigurationStore(defaults: OrganizerProposerTestSupport.makeDefaults())
        let cliPath = enabled
            ? try OrganizerProposerTestSupport.writeExecutableScript(cliBody).path
            : ""
        store.save(CodexAgentConfiguration(isEnabled: enabled, cliPath: cliPath, selectedModel: "test-model"))
        return CodexExplainer(configurationStore: store, runner: CodexOneShotRunner(timeoutSeconds: 30))
    }

    @Test("Disabled agent throws before touching the CLI")
    func disabledThrows() async throws {
        let explainer = try makeExplainer(enabled: false)
        await #expect(throws: CodexExplainError.agentNotEnabled) {
            _ = try await explainer.explain(
                result: makeResult(),
                rule: AIExplanationController.derivedRule(from: makeResult())
            )
        }
    }

    @Test("Last-message prose round-trips into a codex-sourced explanation")
    func happyPath() async throws {
        let explainer = try makeExplainer(
            enabled: true,
            cliBody: writeToOutputFileScript(text: "  This is a cache. Safe to remove.  ")
        )
        let result = makeResult()
        let explanation = try await explainer.explain(
            result: result,
            rule: AIExplanationController.derivedRule(from: result)
        )
        #expect(explanation.source == .codex)
        #expect(explanation.text == "This is a cache. Safe to remove.")
    }

    @Test("canExplain tracks enablement")
    func canExplainTracksEnablement() throws {
        let enabled = try makeExplainer(enabled: true, cliBody: writeToOutputFileScript(text: "x"))
        #expect(enabled.canExplain())
        let disabled = try makeExplainer(enabled: false)
        #expect(!disabled.canExplain())
    }
}
