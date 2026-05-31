import Foundation
import GargantuaLicensing

#if canImport(AppKit)
    import AppKit
#endif

/// Production reader/writer for the user-domain `com.apple.Spotlight`
/// `EnabledPreferenceRules` store.
///
/// `EnabledPreferenceRules` is a flat array of bundle-id strings (verified
/// on-device, and matching Mole #1000). Each entry is either a third-party
/// reverse-DNS bundle id or a `System.*` / `com.apple.*` system rule. Pruning
/// rewrites the array; it never edits the plist file in place, because cfprefsd
/// owns the cache and would clobber a direct file write.
public struct CFPreferencesSpotlightRulesStore: SpotlightRulesReading, SpotlightRulesWriting {
    public static let defaultDomain = "com.apple.Spotlight"
    public static let key = "EnabledPreferenceRules"

    private let domain: String

    public init(domain: String = CFPreferencesSpotlightRulesStore.defaultDomain) {
        self.domain = domain
    }

    public func enabledRuleIdentifiers() -> [String] {
        let value = CFPreferencesCopyAppValue(Self.key as CFString, domain as CFString)
        return (value as? [String]) ?? []
    }

    public func write(keptIdentifiers: [String]) throws {
        // Rewrite through cfprefsd. An empty result drops the key entirely
        // (mirrors Mole #1000's `defaults delete`) so System Settings reflects a
        // fully-clean state rather than a lingering empty array.
        let newValue: CFPropertyList? = keptIdentifiers.isEmpty ? nil : (keptIdentifiers as CFArray)
        CFPreferencesSetAppValue(Self.key as CFString, newValue, domain as CFString)
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            throw SpotlightRulesStoreError.synchronizeFailed
        }
    }
}

public enum SpotlightRulesStoreError: Error, Sendable, Equatable {
    case synchronizeFailed
}

/// Resolves installed apps via LaunchServices through `NSWorkspace`.
public struct WorkspaceInstalledAppResolver: InstalledAppResolving {
    public init() {}

    public func isInstalled(bundleID: String) -> Bool {
        #if canImport(AppKit)
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        #else
            return false
        #endif
    }
}

extension SpotlightOrphanRuleScanner {
    /// Wires the production CFPreferences store, LaunchServices resolver, and
    /// the licensing destructive-action gate.
    public static func live() -> SpotlightOrphanRuleScanner {
        let store = CFPreferencesSpotlightRulesStore()
        return SpotlightOrphanRuleScanner(
            reader: store,
            writer: store,
            resolver: WorkspaceInstalledAppResolver(),
            canExecuteDestructive: {
                if case .allowed = await LicenseGate.shared.canExecuteDestructiveAction() {
                    return true
                }
                return false
            }
        )
    }
}
