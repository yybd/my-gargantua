import Foundation

public extension Bundle {
    /// The `GargantuaCore` resource bundle, resolved WITHOUT touching the
    /// SwiftPM-generated `Bundle.module` accessor.
    ///
    /// `Bundle.module` for this executable target only checks
    /// `Bundle.main.bundleURL/Gargantua_GargantuaCore.bundle` (the `.app` root —
    /// which notarization forbids as sealed content) and an absolute build-dir
    /// path baked in at compile time. In a shipped `.app` both miss, and the
    /// `static let` calls `fatalError` on first access — taking the app down on
    /// the first view render. `Scripts/release/assemble-app.sh` copies the
    /// bundle into `Contents/Resources`, so we resolve it from
    /// `Bundle.main.resourceURL` instead and never evaluate `Bundle.module`.
    static let gargantuaCoreResources: Bundle = {
        let bundleName = "Gargantua_GargantuaCore.bundle"
        let bases = [
            Bundle.main.resourceURL, // shipped .app → Contents/Resources/
            Bundle.main.bundleURL,   // raw `swift build` / `swift run` → beside the binary
        ]
        for base in bases {
            if let url = base?.appendingPathComponent(bundleName),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        #if DEBUG
        // `swift test`: Bundle.main is the xctest host, so the bases above miss;
        // SwiftPM's generated accessor has a valid build-dir path during local
        // builds, so it's safe to fall back to here (and only here).
        return .module
        #else
        // Unreachable for a correctly assembled .app; return main rather than
        // crash so call sites' own fallbacks can run.
        return .main
        #endif
    }()
}
