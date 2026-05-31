import Foundation
import Testing
@testable import GargantuaCore

@Suite("RemnantScanner Spotlight evidence")
struct RemnantScannerSpotlightTests {
    private struct FakeReader: SpotlightRulesReading {
        let ids: [String]
        func enabledRuleIdentifiers() -> [String] { ids }
    }

    private func app(_ bundleID: String) -> AppInfo {
        AppInfo(bundleID: bundleID, name: "Demo", bundlePath: "/Applications/Demo.app", isRunning: false, sizeOnDisk: 100)
    }

    @Test("an app with a Spotlight rule gains a spotlight-rules remnant")
    func detectsRule() throws {
        let scanner = RemnantScanner(rules: [], spotlightRulesReader: FakeReader(ids: ["com.x.y", "com.apple.tips"]))

        let plan = scanner.plan(for: app("com.x.y"), includeAppBundle: false)
        let spot = plan.remnants.filter { $0.category == .spotlightRules }

        #expect(spot.count == 1)
        let item = try #require(spot.first)
        #expect(item.appBundleID == "com.x.y")
        #expect(item.tags.contains("spotlight-pref"))
        #expect(item.safety == .review)
        #expect(item.size == 0)
    }

    @Test("an app without a Spotlight rule gains no such remnant")
    func noRuleNoRemnant() {
        let scanner = RemnantScanner(rules: [], spotlightRulesReader: FakeReader(ids: ["com.other.app"]))

        let plan = scanner.plan(for: app("com.x.y"), includeAppBundle: false)

        #expect(plan.remnants.allSatisfy { $0.category != .spotlightRules })
    }

    @Test("no reader configured means no spotlight evidence")
    func noReaderNoRemnant() {
        let scanner = RemnantScanner(rules: [])

        let plan = scanner.plan(for: app("com.x.y"), includeAppBundle: false)

        #expect(plan.remnants.allSatisfy { $0.category != .spotlightRules })
    }
}
