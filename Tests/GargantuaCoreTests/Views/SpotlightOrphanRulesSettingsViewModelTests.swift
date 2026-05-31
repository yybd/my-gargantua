import Testing
@testable import GargantuaCore

@MainActor
@Suite("SpotlightOrphanRulesSettingsViewModel")
struct SpotlightOrphanRulesSettingsViewModelTests {
    @Test("load surfaces the injected orphans and flips hasLoaded")
    func loadPopulatesOrphans() {
        let model = SpotlightOrphanRulesSettingsViewModel(findOrphans: {
            [SpotlightOrphanRule(identifier: "com.gone.app"), SpotlightOrphanRule(identifier: "com.dead.tool")]
        })

        #expect(model.hasLoaded == false)
        #expect(model.orphans.isEmpty)

        model.load()

        #expect(model.hasLoaded)
        #expect(model.orphans.map(\.identifier) == ["com.gone.app", "com.dead.tool"])
    }

    @Test("load with no orphans still flips hasLoaded")
    func loadWithNoOrphans() {
        let model = SpotlightOrphanRulesSettingsViewModel(findOrphans: { [] })

        model.load()

        #expect(model.hasLoaded)
        #expect(model.orphans.isEmpty)
    }
}
