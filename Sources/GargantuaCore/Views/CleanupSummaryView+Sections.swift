import AppKit
import SwiftUI

extension CleanupSummaryView {

    // MARK: - Narrative loading

    var narrativeLoadingSection: some View {
        HStack(alignment: .center, spacing: GargantuaSpacing.space2) {
            AccretionDiskView(activityRate: 0, size: 14, color: GargantuaColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Composing summary…")
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink2)
                if didShowFirstWarmupAtStart {
                    Text("Compiling shaders for first use…")
                        .font(GargantuaFonts.caption)
                        .foregroundStyle(GargantuaColors.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(GargantuaSpacing.space4)
    }

    // MARK: - Header

    var header: some View {
        let outcome = Self.outcome(for: result)
        let icon: String
        let iconColor: Color
        let title: String
        switch outcome {
        case .complete:
            icon = "checkmark.circle.fill"
            iconColor = GargantuaColors.safe
            title = "Cleanup Complete"
        case .partial:
            icon = "exclamationmark.triangle.fill"
            iconColor = GargantuaColors.review
            title = "Cleanup Partially Complete"
        case .failed:
            icon = "xmark.octagon.fill"
            iconColor = GargantuaColors.protected_
            title = "Cleanup Failed"
        }

        return HStack(spacing: GargantuaSpacing.space2) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GargantuaFonts.heading)
                    .foregroundStyle(GargantuaColors.ink)

                if outcome != .failed {
                    Text("\(AlertItem.formatBytes(result.totalFreed)) freed")
                        .font(GargantuaFonts.monoData)
                        .foregroundStyle(GargantuaColors.safe)
                }
            }

            Spacer()
        }
        .padding(GargantuaSpacing.space4)
    }

    // MARK: - Success Section

    var successSection: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            let count = result.succeededItems.count
            HStack(spacing: GargantuaSpacing.space2) {
                Text(count == 1
                    ? "1 item \(result.cleanupMethod.summaryActionText)"
                    : "\(count) items \(result.cleanupMethod.summaryActionText)")
                    .font(GargantuaFonts.label)
                    .foregroundStyle(GargantuaColors.ink2)

                Spacer()

                // Sort picker lives here (stable position) whenever there is
                // anything sortable visible — always, if there are any items.
                // The picker drives both the succeeded list (when expanded)
                // and the always-rendered failure list below.
                if hasSortableItems {
                    sortPicker
                }

                if count > 0 {
                    Button(action: toggleSucceededExpanded) {
                        HStack(spacing: GargantuaSpacing.space1) {
                            Image(systemName: succeededExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(succeededExpanded ? "Hide items" : "Show items")
                                .font(GargantuaFonts.caption)
                        }
                        .foregroundStyle(GargantuaColors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(succeededExpanded ? "Hide cleaned items" : "Show cleaned items")
                }
            }

            if succeededExpanded, !result.succeededItems.isEmpty {
                itemList(sorted(result.succeededItems), foreground: GargantuaColors.ink)
            }
        }
        .padding(GargantuaSpacing.space4)
    }

    // MARK: - Failure Section

    private var permissionFailureCount: Int {
        result.failedItems.filter {
            CleanupFailureClassifier.isElevatable($0.error)
        }.count
    }

    /// Pick the remediation that matches the *real* cause. Full Disk Access is
    /// only the blocker when it is genuinely missing — when it is granted, a
    /// permission failure means the items are owned by macOS or another user
    /// (needs elevated removal) or Finder Automation was denied, not a toggle
    /// the user has already flipped.
    private var dominantFailureGuidance: PermissionFailureGuidance? {
        guard !result.failedItems.isEmpty,
              permissionFailureCount * 2 >= result.failedItems.count
        else { return nil }

        if !PermissionChecker.hasFullDiskAccess {
            return .fullDiskAccess
        }

        let automationCount = result.failedItems.filter {
            CleanupFailureClassifier.kind(of: $0.error) == .automation
        }.count
        if automationCount * 2 >= permissionFailureCount {
            return .automation
        }

        // Ownership failure: the remedy depends on the helper's *actual* state,
        // not just "permission failed". Telling the user to approve a helper that
        // is already enabled (and doesn't appear as a separate toggle) is a dead
        // end — that was the original confusion.
        switch SMAppServicePrivilegedHelperInstaller().status() {
        case .notFound:
            // No embedded helper (AGPL source build or a fork signed by another
            // team) — point at the signed release, not an approval toggle.
            return .systemUnavailable
        case .requiresApproval, .notRegistered:
            // Genuinely needs the user to approve it.
            return .ownership
        case .enabled, .unknown:
            // Helper is active but these items still couldn't be removed — they
            // are owned by root / another user or in use (e.g. root-owned items
            // sitting in Trash). No approval will help; show the honest reasons.
            return .systemResidual
        }
    }

    var failureSection: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            let count = result.failedItems.count
            HStack(spacing: GargantuaSpacing.space2) {
                Circle()
                    .fill(GargantuaColors.protected_)
                    .frame(width: 6, height: 6)
                Text(count == 1 ? "1 item failed" : "\(count) items failed")
                    .font(GargantuaFonts.label)
                    .foregroundStyle(GargantuaColors.protected_)

                Spacer()
            }

            if let guidance = dominantFailureGuidance {
                PermissionFailurePrompt(guidance: guidance)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sorted(result.failedItems), id: \.item.id) { failed in
                        HStack(spacing: GargantuaSpacing.space2) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failed.item.name)
                                    .font(GargantuaFonts.label)
                                    .foregroundStyle(GargantuaColors.ink)
                                    .lineLimit(1)

                                if let error = failed.error {
                                    Text(error)
                                        .font(GargantuaFonts.caption)
                                        .foregroundStyle(GargantuaColors.ink3)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Text(AlertItem.formatBytes(failed.item.size))
                                .font(GargantuaFonts.monoData)
                                .foregroundStyle(GargantuaColors.ink3)
                        }
                        .padding(.vertical, GargantuaSpacing.space1)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(GargantuaSpacing.space4)
    }

    // MARK: - Shared item list

    var sortPicker: some View {
        GargantuaSegmentedPicker(
            selection: $sort,
            options: SummarySort.allCases.map { (value: $0, label: $0.label) },
            accessibilityLabel: "Sort cleanup items"
        )
        .frame(width: 140)
    }

    func itemList(_ items: [CleanupItemResult], foreground: Color) -> some View {
        // Cap the inline list height so an app like Xcode with hundreds of
        // remnants can't push the footer off-screen; scroll inside the card.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.item.id) { entry in
                    HStack(spacing: GargantuaSpacing.space2) {
                        Text(entry.item.name)
                            .font(GargantuaFonts.caption)
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: GargantuaSpacing.space2)

                        // Size text gets layout priority so a long app name
                        // truncates before the byte count does.
                        Text(AlertItem.formatBytes(entry.item.size))
                            .font(GargantuaFonts.monoData)
                            .foregroundStyle(GargantuaColors.ink3)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    // MARK: - Helpers

    /// Size descending with name as the deterministic tiebreaker so rows
    /// don't reshuffle between refreshes when sizes match. Name sort is
    /// case-insensitive so "AppCleaner" and "aria2" sort lexically.
    func sorted(_ items: [CleanupItemResult]) -> [CleanupItemResult] {
        switch sort {
        case .name:
            items.sorted {
                $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending
            }
        case .size:
            items.sorted {
                if $0.item.size != $1.item.size {
                    return $0.item.size > $1.item.size
                }
                return $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending
            }
        }
    }

    /// True if there is at least one item (succeeded or failed) that the
    /// user could plausibly want to sort.
    var hasSortableItems: Bool {
        !result.succeededItems.isEmpty || !result.failedItems.isEmpty
    }

    func toggleSucceededExpanded() {
        if reduceMotion {
            succeededExpanded.toggle()
        } else {
            withAnimation(.easeOut(duration: 0.18)) { succeededExpanded.toggle() }
        }
    }

    // MARK: - Footer Actions

    var footerActions: some View {
        HStack(spacing: GargantuaSpacing.space3) {
            // Audit trail link
            Button(action: openAuditTrail) {
                HStack(spacing: GargantuaSpacing.space1) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                    Text("View Audit Trail")
                        .font(GargantuaFonts.caption)
                }
                .foregroundStyle(GargantuaColors.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            if result.cleanupMethod == .trash {
                // Undo - reveal Trash
                Button(action: revealTrash) {
                    HStack(spacing: GargantuaSpacing.space1) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Reveal Trash")
                            .font(GargantuaFonts.label)
                    }
                    .foregroundStyle(GargantuaColors.ink)
                    .padding(.vertical, GargantuaSpacing.space2)
                    .padding(.horizontal, GargantuaSpacing.space3)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: GargantuaRadius.small)
                            .stroke(GargantuaColors.borderEm, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Done
            Button(action: onDismiss) {
                Text("Done")
                    .font(GargantuaFonts.label)
                    .foregroundStyle(.white)
                    .padding(.vertical, GargantuaSpacing.space2)
                    .padding(.horizontal, GargantuaSpacing.space4)
                    .background(GargantuaColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(GargantuaSpacing.space4)
    }

    // MARK: - Actions

    func revealTrash() {
        TrashRevealer().revealCleanupResult(result)
    }

    func openAuditTrail() {
        let logFile = AuditWriter().logFile
        if FileManager.default.fileExists(atPath: logFile.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logFile])
        }
    }
}

// MARK: - Permission Failure Prompt

enum PermissionFailureGuidance {
    /// Full Disk Access is genuinely missing.
    case fullDiskAccess
    /// Finder Automation (Apple Events) was denied.
    case automation
    /// Items are owned by macOS or another user; the privileged helper is
    /// present but needs approval.
    case ownership
    /// Items are owned by the system but this build ships no privileged helper
    /// (an AGPL source build, or a fork signed by another team), so elevated
    /// removal can never work here.
    case systemUnavailable
    /// The privileged helper is active, but these items still couldn't be
    /// removed — owned by root / another user, or in use. No approval helps.
    case systemResidual

    var title: String {
        switch self {
        case .fullDiskAccess: "These items require Full Disk Access"
        case .automation: "These items need Automation permission"
        case .ownership: "These items are owned by the system"
        case .systemUnavailable: "This build can't remove system-owned items"
        case .systemResidual: "Some items couldn't be removed"
        }
    }

    var detail: String {
        switch self {
        case .fullDiskAccess:
            "Open System Settings, click the \"+\" button, then add Gargantua from your Applications folder."
        case .automation:
            "Gargantua moves items to the Trash through Finder. Allow it to control Finder under Automation, "
                + "or it will fall back to the direct Trash API."
        case .ownership:
            "Full Disk Access can't delete files owned by macOS or another user. Approve Gargantua's privileged "
                + "helper under Login Items & Extensions so it can remove them, then run the clean again."
        case .systemUnavailable:
            "Files owned by macOS or another user need Gargantua's privileged helper, which only the signed "
                + "release ships. Install it with Homebrew (brew install --cask gargantua), or build from source "
                + "with your own Developer ID. Files you own were still cleaned."
        case .systemResidual:
            "These are owned by macOS or another user, or are in use by a running app (for example a root-owned "
                + "app already in the Trash), so they couldn't be removed even with Gargantua's privileged helper. "
                + "Each item's reason is shown below; the rest were cleaned."
        }
    }

    /// Some states have no actionable button — the situation is informational.
    var buttonLabel: String? {
        switch self {
        case .fullDiskAccess: "Open Full Disk Access Settings"
        case .automation: "Open Automation Settings"
        case .ownership: "Open Login Items & Extensions"
        case .systemUnavailable: "Get the Signed Release"
        case .systemResidual: nil
        }
    }

    var buttonIcon: String {
        switch self {
        case .fullDiskAccess, .automation, .ownership: "gear"
        case .systemUnavailable: "arrow.down.circle"
        case .systemResidual: "info.circle"
        }
    }

    var actionURL: URL? {
        switch self {
        case .fullDiskAccess:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .ownership:
            URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        case .systemUnavailable:
            URL(string: "https://github.com/inceptyon-labs/gargantua/releases/latest")
        case .systemResidual:
            nil
        }
    }
}

struct PermissionFailurePrompt: View {
    let guidance: PermissionFailureGuidance

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            HStack(spacing: GargantuaSpacing.space2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(GargantuaColors.review)

                Text(guidance.title)
                    .font(GargantuaFonts.label)
                    .foregroundStyle(GargantuaColors.ink)
            }

            Text(guidance.detail)
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if let actionURL = guidance.actionURL, let buttonLabel = guidance.buttonLabel {
                Button {
                    openURL(actionURL)
                } label: {
                    HStack(spacing: GargantuaSpacing.space1) {
                        Image(systemName: guidance.buttonIcon)
                            .font(.system(size: 11))
                        Text(buttonLabel)
                            .font(GargantuaFonts.caption)
                    }
                    .foregroundStyle(GargantuaColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(GargantuaSpacing.space3)
        .background(GargantuaColors.review.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: GargantuaRadius.small)
                .stroke(GargantuaColors.review.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
    }
}
