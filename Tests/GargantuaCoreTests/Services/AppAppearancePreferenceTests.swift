import SwiftUI
import Testing
@testable import GargantuaCore

@Suite("AppAppearance")
struct AppAppearancePreferenceTests {
    @Test("dark is the default appearance")
    func darkIsDefault() {
        #expect(AppAppearance.defaultValue == .dark)
    }

    @Test("init(storedValue:) round-trips every known raw value")
    func initFromKnownRawValues() {
        #expect(AppAppearance(storedValue: "system") == .system)
        #expect(AppAppearance(storedValue: "light") == .light)
        #expect(AppAppearance(storedValue: "dark") == .dark)
    }

    @Test("init(storedValue:) falls back to the default for nil or junk")
    func initFallsBack() {
        #expect(AppAppearance(storedValue: nil) == .dark)
        #expect(AppAppearance(storedValue: "chartreuse") == .dark)
        #expect(AppAppearance(storedValue: "") == .dark)
    }

    @Test("id mirrors the raw value")
    func idMirrorsRawValue() {
        for appearance in AppAppearance.allCases {
            #expect(appearance.id == appearance.rawValue)
        }
    }

    @Test("every appearance has a non-empty label and icon")
    func labelsAndIconsPresent() {
        for appearance in AppAppearance.allCases {
            #expect(!appearance.label.isEmpty)
            #expect(!appearance.icon.isEmpty)
        }
    }

    @Test("colorScheme forces light/dark and follows the system otherwise")
    func colorSchemeMapping() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("nsAppearance forces aqua/darkAqua and follows the system otherwise")
    func nsAppearanceMapping() {
        #expect(AppAppearance.system.nsAppearance == nil)
        #expect(AppAppearance.light.nsAppearance?.name == .aqua)
        #expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
    }
}
