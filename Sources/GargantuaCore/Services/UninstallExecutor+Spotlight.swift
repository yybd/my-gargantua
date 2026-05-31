import Foundation

extension UninstallExecutor {
    /// Remove Spotlight preference-rule remnants through cfprefsd (not the
    /// Trash) and return their cleanup results. Each remnant's `appBundleID` is
    /// dropped from `com.apple.Spotlight` `EnabledPreferenceRules`.
    func removeSpotlightRules(_ remnants: [RemnantItem]) -> [CleanupItemResult] {
        remnants.map { remnant in
            let scan = remnant.toScanResult()
            let result: CleanupItemResult
            do {
                try spotlightRuleRemover.remove(bundleID: remnant.appBundleID)
                result = CleanupItemResult(item: scan, succeeded: true)
            } catch {
                result = CleanupItemResult(item: scan, succeeded: false, error: error.localizedDescription)
            }
            emit(result: result, item: scan)
            return result
        }
    }
}
