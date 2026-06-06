import Foundation
import Testing
@testable import GargantuaCore

@MainActor
private func makeController() throws -> PersistenceController {
    try PersistenceController(inMemory: true)
}

@Suite("PersistenceController bootstrap and profiles")
@MainActor
struct PersistenceControllerProfilesTests {

    // MARK: - Bootstrap

    @Test("Bootstrap seeds built-in profiles and default settings")
    func bootstrap() throws {
        let ctrl = try makeController()
        try ctrl.bootstrap()

        let profiles = try ctrl.fetchProfiles()
        #expect(profiles.count == CleanupProfile.builtIn.count)
        #expect(profiles.contains(where: { $0.id == "developer" }))
        #expect(profiles.contains(where: { $0.id == "light" }))
        #expect(profiles.contains(where: { $0.id == "deep" }))

        let settings = try ctrl.fetchSettings()
        #expect(settings.activeProfileID == "developer")
        #expect(settings.retentionDays == 90)
    }

    @Test("Bootstrap strips a stale override from a persisted built-in profile")
    func bootstrapReconcilesBuiltIns() throws {
        let ctrl = try makeController()
        // Simulate an old build's seeded `deep` profile carrying the black-box
        // age>7d→safe override that current code no longer ships.
        let stale = CleanupProfile(
            id: "deep",
            name: "Deep Clean",
            description: "stale",
            categories: ["system_logs"],
            safetyOverrides: [
                SafetyOverride(condition: "age > 7d", safety: .safe, profiles: ["deep"]),
            ],
            isCustom: false
        )
        try ctrl.saveProfile(stale)

        try ctrl.bootstrap()

        let deep = try ctrl.fetchProfiles().first { $0.id == "deep" }
        #expect(deep?.safetyOverrides.isEmpty == true)
    }

    @Test("Bootstrap leaves a user's custom profile overrides intact")
    func bootstrapPreservesCustomProfiles() throws {
        let ctrl = try makeController()
        let custom = CleanupProfile(
            id: "my-custom",
            name: "Mine",
            description: "user profile",
            categories: ["app_cache"],
            safetyOverrides: [
                SafetyOverride(condition: "age > 7d", safety: .safe, profiles: ["my-custom"]),
            ],
            isCustom: true
        )
        try ctrl.saveProfile(custom)

        try ctrl.bootstrap()

        let fetched = try ctrl.fetchProfiles().first { $0.id == "my-custom" }
        #expect(fetched?.safetyOverrides.count == 1)
    }

    @Test("Bootstrap is idempotent — does not duplicate data")
    func bootstrapIdempotent() throws {
        let ctrl = try makeController()
        try ctrl.bootstrap()
        try ctrl.bootstrap()
        try ctrl.bootstrap()

        let profiles = try ctrl.fetchProfiles()
        #expect(profiles.count == CleanupProfile.builtIn.count)
    }

    // MARK: - Profiles

    @Test("Save and fetch a custom profile")
    func saveAndFetchProfile() throws {
        let ctrl = try makeController()

        let custom = CleanupProfile(
            id: "custom",
            name: "My Profile",
            description: "Custom test profile",
            categories: ["browser_cache", "system_logs"],
            isCustom: true
        )
        try ctrl.saveProfile(custom)

        let profiles = try ctrl.fetchProfiles()
        #expect(profiles.count == 1)

        let fetched = profiles[0]
        #expect(fetched.id == "custom")
        #expect(fetched.name == "My Profile")
        #expect(fetched.categories == ["browser_cache", "system_logs"])
        #expect(fetched.isCustom == true)
    }

    @Test("Update existing profile preserves ID")
    func updateProfile() throws {
        let ctrl = try makeController()

        let original = CleanupProfile(
            id: "custom",
            name: "Original",
            description: "V1",
            categories: ["browser_cache"],
            isCustom: true
        )
        try ctrl.saveProfile(original)

        let updated = CleanupProfile(
            id: "custom",
            name: "Updated",
            description: "V2",
            categories: ["browser_cache", "system_cache"],
            isCustom: true
        )
        try ctrl.saveProfile(updated)

        let profiles = try ctrl.fetchProfiles()
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "Updated")
        #expect(profiles[0].categories.count == 2)
    }

    @Test("Delete profile by ID")
    func deleteProfile() throws {
        let ctrl = try makeController()
        try ctrl.bootstrap()

        let beforeCount = try ctrl.fetchProfiles().count
        try ctrl.deleteProfile(id: "light")
        let afterCount = try ctrl.fetchProfiles().count

        #expect(afterCount == beforeCount - 1)
    }

    @Test("Profile with safety overrides round-trips correctly")
    func profileOverridesRoundTrip() throws {
        let ctrl = try makeController()

        // Built-in profiles ship no blanket overrides (rules are the source of
        // truth), so exercise persistence with a user-authored profile that does.
        let custom = CleanupProfile(
            id: "custom-overrides",
            name: "Custom",
            description: "User profile with an override",
            categories: ["dev_artifacts"],
            safetyOverrides: [
                SafetyOverride(condition: "age > 30d", safety: .safe, profiles: ["custom-overrides"]),
            ],
            isCustom: true
        )
        try ctrl.saveProfile(custom)

        let fetched = try ctrl.fetchProfiles().first(where: { $0.id == "custom-overrides" })
        #expect(fetched != nil)
        #expect(fetched!.safetyOverrides.count == 1)
        #expect(fetched!.safetyOverrides[0].condition == "age > 30d")
    }
}
