import SwiftUI

/// Storage-tab section that lists orphaned `com.apple.Spotlight` preference
/// rules — dead third-party bundle ids left in System Settings → Spotlight
/// after an app is uninstalled — and offers a license-gated batch removal.
///
/// Detection layers LaunchServices → mdfind → filesystem scan so an installed
/// app is never mistaken for "gone". `System.*` / `com.apple.*` rules are never
/// touched. Removal rewrites the array through cfprefsd (`SpotlightOrphanRuleScanner.prune()`).
@MainActor
final class SpotlightOrphanRulesSettingsViewModel: ObservableObject {
    enum Notice: Equatable {
        case removed(Int)
        case alreadyClean
        case blocked
        case failed(String)
    }

    @Published private(set) var orphans: [SpotlightOrphanRule] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isPruning = false
    @Published private(set) var notice: Notice?

    private let scanner: SpotlightOrphanRuleScanner

    init(scanner: SpotlightOrphanRuleScanner = .live()) {
        self.scanner = scanner
    }

    func load() {
        orphans = scanner.findOrphans()
        hasLoaded = true
    }

    func prune() async {
        isPruning = true
        defer { isPruning = false }
        do {
            let outcome = try await scanner.prune()
            orphans = scanner.findOrphans()
            notice = outcome.didWrite ? .removed(outcome.removed.count) : .alreadyClean
        } catch SpotlightOrphanRuleScanner.PruneError.destructiveActionBlocked {
            notice = .blocked
        } catch {
            notice = .failed(error.localizedDescription)
        }
    }
}

struct SpotlightOrphanRulesSettingsSection: View {
    @StateObject private var model = SpotlightOrphanRulesSettingsViewModel()
    @State private var showingConfirm = false

    var body: some View {
        SettingsSectionContainer(
            "Spotlight Rules",
            subtitle: "Uninstalled apps can leave dead entries in System Settings → Spotlight. "
                + "Gargantua removes the orphaned ones; system and Apple rules are always kept.",
            count: model.hasLoaded ? model.orphans.count : nil
        ) {
            if let notice = model.notice {
                SettingsNoticeRow(
                    icon: noticeIcon(notice),
                    message: noticeMessage(notice),
                    tone: noticeTone(notice)
                )
            }

            if model.orphans.isEmpty {
                emptyRow
            } else {
                VStack(spacing: 1) {
                    ForEach(model.orphans) { orphan in
                        orphanRow(orphan)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))

                pruneRow
            }
        }
        .task { model.load() }
        .sheet(isPresented: $showingConfirm) {
            DestructiveConfirmSheet(
                title: "Remove orphaned Spotlight rules?",
                message: "Gargantua will drop \(model.orphans.count) Spotlight rule(s) whose apps are no longer installed. "
                    + "System and Apple rules are never touched. Reinstalling an app restores its rule.",
                confirmLabel: "Remove \(model.orphans.count) rule\(model.orphans.count == 1 ? "" : "s")",
                onCancel: { showingConfirm = false },
                onConfirm: {
                    showingConfirm = false
                    Task { await model.prune() }
                }
            )
        }
    }

    private var pruneRow: some View {
        HStack {
            Spacer()
            GargantuaButton(
                model.isPruning ? "Removing…" : "Remove orphaned rules",
                icon: "trash",
                tone: .destructive,
                isDisabled: model.isPruning,
                action: { showingConfirm = true }
            )
            .help("Remove Spotlight rules for uninstalled apps")
        }
    }

    private var emptyRow: some View {
        HStack(spacing: GargantuaSpacing.space2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(GargantuaColors.ink3)
            Text(model.hasLoaded ? "No orphaned Spotlight rules found." : "Checking…")
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)
        }
        .padding(.vertical, GargantuaSpacing.space1)
    }

    private func orphanRow(_ orphan: SpotlightOrphanRule) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GargantuaSpacing.space3) {
            Image(systemName: "app.dashed")
                .font(.system(size: 12))
                .foregroundStyle(GargantuaColors.ink3)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(orphan.identifier)
                    .font(GargantuaFonts.monoPath)
                    .foregroundStyle(GargantuaColors.ink)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Text("App not installed — leftover Spotlight rule")
                    .font(GargantuaFonts.caption)
                    .foregroundStyle(GargantuaColors.ink3)
                    .lineLimit(1)
            }

            Spacer(minLength: GargantuaSpacing.space3)
        }
        .padding(.horizontal, GargantuaSpacing.space3)
        .padding(.vertical, GargantuaSpacing.space2)
        .background(GargantuaColors.surface1)
        .contentShape(Rectangle())
    }

    private func noticeIcon(_ notice: SpotlightOrphanRulesSettingsViewModel.Notice) -> String {
        switch notice {
        case .removed, .alreadyClean: return "checkmark.circle.fill"
        case .blocked: return "lock.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func noticeTone(_ notice: SpotlightOrphanRulesSettingsViewModel.Notice) -> SettingsNoticeRow.Tone {
        switch notice {
        case .removed, .alreadyClean: return .safe
        case .blocked, .failed: return .protected
        }
    }

    private func noticeMessage(_ notice: SpotlightOrphanRulesSettingsViewModel.Notice) -> String {
        switch notice {
        case .removed(let count):
            return "Removed \(count) orphaned Spotlight rule\(count == 1 ? "" : "s")."
        case .alreadyClean:
            return "Spotlight rules are already clean."
        case .blocked:
            return "Removing rules needs an active license or trial."
        case .failed(let message):
            return message
        }
    }
}
