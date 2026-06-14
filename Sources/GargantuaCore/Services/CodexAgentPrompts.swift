import Foundation

/// Built-in agent prompt templates surfaced in the Codex Agent Run UI.
///
/// Unlike the Claude Code agent, Codex runs one-shot via `codex exec` with no
/// Gargantua MCP server — it inspects the real filesystem through its own
/// read-only shell/read tools and returns a written report. The templates
/// mirror the Claude set so the two engines feel like siblings, but the
/// instructions are honest about Codex's narrower, read-only reach.
public enum CodexAgentPromptTemplate: String, CaseIterable, Identifiable, Sendable {
    /// Investigate disk-space usage and propose safe cleanup.
    case investigateSpace
    /// Inspect a development directory for stale projects and artifacts.
    case projectArchaeology
    /// Generate a reviewable maintenance script.
    case customCleanupScript

    /// Stable identifier used by SwiftUI lists and pickers.
    public var id: String { rawValue }

    /// Short user-facing template name.
    public var title: String {
        switch self {
        case .investigateSpace: "Audit Disk Space"
        case .projectArchaeology: "Find Stale Dev Projects"
        case .customCleanupScript: "Generate Cleanup Script"
        }
    }

    /// SF Symbol used for the template icon.
    public var icon: String {
        switch self {
        case .investigateSpace: "magnifyingglass.circle"
        case .projectArchaeology: "folder.badge.questionmark"
        case .customCleanupScript: "terminal"
        }
    }

    /// One-line description shown directly under the picker.
    public var summary: String {
        switch self {
        case .investigateSpace:
            "Codex inspects the filesystem read-only (du, ls, reading files) and returns a written cleanup report. "
                + "Nothing is deleted — the sandbox blocks writes."
        case .projectArchaeology:
            "Looks at a development directory you specify, flagging stale repos, build artifacts, "
                + "and archive candidates. Produces a written report; the read-only sandbox can't touch files."
        case .customCleanupScript:
            "Produces a reviewable shell script with every command annotated. The script is shown for review only — Codex never runs it."
        }
    }

    /// Placeholder user context shown in the prompt input field.
    public var placeholder: String {
        switch self {
        case .investigateSpace:
            "Find the biggest safe cleanup opportunities on this Mac."
        case .projectArchaeology:
            "Inspect ~/Development/example-project and identify old repos or artifacts I can archive."
        case .customCleanupScript:
            "Generate a reviewable maintenance script for stale build artifacts."
        }
    }

    /// The "Goal:" sentence stamped into the prompt builder.
    public var baseGoal: String {
        switch self {
        case .investigateSpace:
            "Investigate what is taking disk space and produce an evidence-backed cleanup report."
        case .projectArchaeology:
            "Perform project archaeology: identify stale repositories, generated artifacts, and low-risk archive candidates."
        case .customCleanupScript:
            "Generate a custom cleanup script proposal. Do not run it; produce the script and explain every command."
        }
    }
}

/// Builds the text prompts handed to the one-shot Codex agent (`codex exec`).
public enum CodexAgentPromptBuilder {
    /// Builds an agent prompt for a template and trimmed user-supplied context.
    public static func prompt(
        template: CodexAgentPromptTemplate,
        userContext: String
    ) -> String {
        let trimmedContext = userContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = trimmedContext.isEmpty ? template.placeholder : trimmedContext
        // swiftlint:disable line_length
        return """
        You are running inside Gargantua's Codex agent mode — a single read-only `codex exec` run.

        Goal:
        \(template.baseGoal)

        User context:
        \(context)

        How you work here:
        - You are NOT connected to Gargantua's scan engine. Inspect the real filesystem yourself with your read-only tools (e.g. `du`, `ls`, `find`, reading files). The sandbox is read-only, so any write/delete will fail — never attempt one.
        - Be frugal: a handful of targeted commands beats crawling the whole disk. Start from the most likely space sinks (caches, build artifacts, downloads, large dev directories) unless the user pointed you somewhere specific.
        - Reason from what you actually observed. Do not invent file sizes or paths you didn't inspect.

        Safety rules:
        - Never delete, move, overwrite, chmod, chown, or edit files. You cannot, and you must not propose doing so directly — point the user to Gargantua's Deep Scan or Smart Uninstaller for any actual removal.
        - Treat anything under system, application-support data, and signed app bundles as off-limits for cleanup suggestions.

        Output rules:
        - Your deliverable is this written report. Return concise prose: what you inspected, the evidence (paths + sizes), proposed cleanup candidates ranked by safety, and anything you deliberately left alone and why.
        - Do not use shell output redirection (>, >>, tee) to write a report file — return the report as your final message.
        """
        // swiftlint:enable line_length
    }

    /// Builds a post-scheduled-scan audit prompt using the supplied scan summary.
    /// Scheduled audits run unattended and read-only.
    public static func scheduledAuditPrompt(summary: ScheduledScanSummary) -> String {
        // swiftlint:disable line_length
        let context = """
        Scheduled scan completed at \(summary.date.formatted(date: .abbreviated, time: .shortened)).
        Profile: \(summary.profileID)
        Actionable items: \(summary.itemCount)
        Reclaimable bytes: \(summary.reclaimableBytes)
        Produce a maintenance audit report. Do not clean anything.
        """
        return """
        You are running inside Gargantua's Codex agent mode (scheduled-audit hook) — a single read-only `codex exec` run.

        Goal:
        \(CodexAgentPromptTemplate.investigateSpace.baseGoal)

        Context from the scheduled scan that just finished:
        \(context)

        How you work here:
        - You are NOT connected to Gargantua's scan engine; the numbers above are all you were handed. You may corroborate them with your own read-only tools (`du`, `ls`, reading files), but stay frugal — this is an unattended run.
        - The sandbox is read-only. Never attempt to delete, move, or modify anything.

        Output rules:
        - Return a concise maintenance audit report: what the scan found, where the reclaimable space likely lives, proposed cleanup candidates ranked by safety, and any risky items you'd skip. Recommend Gargantua's Deep Scan / Smart Uninstaller for the actual removal.
        - Do not create files or use shell output redirection — the report is your final message.
        """
        // swiftlint:enable line_length
    }
}
