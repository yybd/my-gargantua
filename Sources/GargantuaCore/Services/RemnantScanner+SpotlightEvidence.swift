import Foundation

/// Spotlight preference-rule evidence for `RemnantScanner`.
///
/// When an app has a `com.apple.Spotlight` `EnabledPreferenceRules` entry, that
/// entry becomes a dead "Search results" row in System Settings → Spotlight
/// once the app is removed. Surfacing it as a remnant lets the Smart Uninstaller
/// clear it as part of the uninstall instead of leaving an orphan behind.
///
/// This is a non-file remnant (category `.spotlightRules`): `UninstallExecutor`
/// routes it to a cfprefsd rewrite rather than the Trash.
extension RemnantScanner {
    func appendSpotlightRuleEvidence(into remnants: inout [RemnantItem], for app: AppInfo) {
        guard let spotlightRulesReader else { return }
        guard spotlightRulesReader.enabledRuleIdentifiers().contains(app.bundleID) else { return }

        let item = RemnantItem(
            id: "spotlight-rule-\(app.bundleID)",
            appBundleID: app.bundleID,
            category: .spotlightRules,
            path: "Spotlight rule (\(app.bundleID))",
            size: 0,
            safety: .review,
            confidence: 80,
            explanation: "Spotlight search-rule entry in System Settings → Spotlight. "
                + "Removing it with the app prevents a dead row from lingering.",
            source: SourceAttribution(name: app.displayName ?? app.name),
            ruleID: "spotlight-pref:\(app.bundleID)",
            tags: ["spotlight-pref"]
        )
        remnants.append(item)
        observer?.didEmit(ScanProgressEvent(path: item.path, outcome: .match, bytes: 0))
    }
}
