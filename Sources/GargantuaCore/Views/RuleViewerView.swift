import SwiftUI

private let communityRulesRepositoryURL = URL(string: "https://github.com/inceptyon-labs/gargantua-rules")!

/// Rule Viewer — browse cleanup rules by category with YAML display and exclusion management.
///
/// Three-column layout: category list (browser/developer/system) → rule list → rule detail.
/// Detail pane shows safety level, confidence, explanation, source, and raw YAML.
/// Bottom section manages the path exclusions persisted via SwiftData.
public struct RuleViewerView: View {
    let persistence: PersistenceController
    /// Supplied by the app so the Rules screen can trigger the same Sparkle
    /// update check that ships new rules. `nil` in previews/standalone use.
    let updateSettingsViewModel: AppUpdateSettingsViewModel?

    @State var categories: [RuleCategory] = []
    @State var selectedCategory: String?
    @State var selectedRuleID: String?
    @State private var isLoading = true

    public init(
        persistence: PersistenceController,
        updateSettingsViewModel: AppUpdateSettingsViewModel? = nil
    ) {
        self.persistence = persistence
        self.updateSettingsViewModel = updateSettingsViewModel
    }

    var selectedCategoryRules: [ScanRule] {
        categories.first(where: { $0.name == selectedCategory })?.rules ?? []
    }

    var selectedRule: ScanRule? {
        selectedCategoryRules.first(where: { $0.id == selectedRuleID })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if isLoading {
                AccretionDiskView(activityRate: 12, size: 36, color: GargantuaColors.accretion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    categoryAndRuleList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GargantuaColors.void_)
        .task {
            await loadRules()
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: GargantuaSpacing.space2) {
            HStack {
                Text("Rules")
                    .font(GargantuaFonts.heading)
                    .foregroundStyle(GargantuaColors.ink)

                Spacer()

                Link(destination: communityRulesRepositoryURL) {
                    Label("Contribute Rules", systemImage: "arrow.up.right.square")
                        .font(GargantuaFonts.label)
                        .foregroundStyle(GargantuaColors.accent)
                        .padding(.horizontal, GargantuaSpacing.space3)
                        .padding(.vertical, GargantuaSpacing.space2)
                        .background(GargantuaColors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: GargantuaRadius.small))
                }
                .buttonStyle(.plain)
                .help("Open the public gargantua-rules repository")

                if isLoading {
                    AccretionDiskView(activityRate: 18, size: 12, color: GargantuaColors.accretion)
                }
            }

            rulesCurrencyLine
        }
        .padding(.horizontal, GargantuaSpacing.space6)
        .padding(.top, GargantuaSpacing.space6)
        .padding(.bottom, GargantuaSpacing.space3)
    }

    /// Passive provenance line: rules are bundled and reviewed per release, so
    /// new rules arrive with app updates. Wired to the same Sparkle check as the
    /// menu command rather than implying a live rule fetch.
    private var rulesCurrencyLine: some View {
        HStack(spacing: GargantuaSpacing.space2) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 11))
                .foregroundStyle(GargantuaColors.safe)

            Text("Reviewed and bundled with this release. New rules arrive with app updates.")
                .font(GargantuaFonts.caption)
                .foregroundStyle(GargantuaColors.ink3)

            if let updateSettingsViewModel {
                Button("Check for Updates") {
                    updateSettingsViewModel.userCheckForUpdates()
                }
                .buttonStyle(.plain)
                .font(GargantuaFonts.caption.weight(.semibold))
                .foregroundStyle(GargantuaColors.accent)
                .help("Check for a Gargantua update, which includes the latest reviewed rules")
            }
        }
    }

    func safetyColor(_ level: SafetyLevel) -> Color {
        switch level {
        case .safe: GargantuaColors.safe
        case .review: GargantuaColors.review
        case .protected_: GargantuaColors.protected_
        }
    }

    private func loadRules() async {
        isLoading = true
        let loader = RuleLoader()
        guard let rulesURL = RuleDirectoryResolver.resolve() else {
            isLoading = false
            return
        }

        do {
            let result = try loader.loadRules(from: rulesURL)
            let grouped = Dictionary(grouping: result.rules) { rule -> String in
                if rule.category.hasPrefix("browser") { return "browser" }
                if rule.category.hasPrefix("app") || rule.tags.contains("app") {
                    return "apps"
                }
                if rule.tags.contains("developer") || rule.category.hasPrefix("dev")
                    || rule.category.hasPrefix("build") || rule.category.hasPrefix("package") {
                    return "developer"
                }
                return "system"
            }

            categories = ["browser", "apps", "developer", "system"].compactMap { name in
                guard let rules = grouped[name], !rules.isEmpty else { return nil }
                return RuleCategory(name: name, rules: rules.sorted { $0.name < $1.name })
            }

            if selectedCategory == nil {
                selectedCategory = categories.first?.name
            }
        } catch {
            categories = []
        }
        isLoading = false
    }
}
