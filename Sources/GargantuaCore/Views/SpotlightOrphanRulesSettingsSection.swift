import SwiftUI

/// Read-only Storage-tab section listing orphaned `com.apple.Spotlight`
/// preference rules — dead third-party bundle ids left in System Settings →
/// Spotlight after an app is uninstalled.
///
/// This is detection-only for now: it surfaces what `SpotlightOrphanRuleScanner`
/// finds without offering removal. Wiring the (license-gated) prune into a
/// destructive action is tracked separately, pending on-device validation of
/// the live preference shape.
@MainActor
final class SpotlightOrphanRulesSettingsViewModel: ObservableObject {
    @Published private(set) var orphans: [SpotlightOrphanRule] = []
    @Published private(set) var hasLoaded = false

    private let findOrphans: @Sendable () -> [SpotlightOrphanRule]

    init(findOrphans: @escaping @Sendable () -> [SpotlightOrphanRule] = {
        SpotlightOrphanRuleScanner.live().findOrphans()
    }) {
        self.findOrphans = findOrphans
    }

    func load() {
        orphans = findOrphans()
        hasLoaded = true
    }
}

struct SpotlightOrphanRulesSettingsSection: View {
    @StateObject private var model = SpotlightOrphanRulesSettingsViewModel()

    var body: some View {
        SettingsSectionContainer(
            "Spotlight Rules",
            subtitle: "Uninstalled apps can leave dead entries in System Settings → Spotlight. "
                + "These are detected for review; removal is not yet available here.",
            count: model.hasLoaded ? model.orphans.count : nil
        ) {
            if model.orphans.isEmpty {
                emptyRow
            } else {
                VStack(spacing: 1) {
                    ForEach(model.orphans) { orphan in
                        orphanRow(orphan)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
            }
        }
        .task { model.load() }
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
}
