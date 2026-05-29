import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseStore")
struct LicenseStoreTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gargantua-licensing-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }

    private func makeStore(
        at url: URL,
        client: MockPolarClient,
        grace: TimeInterval = LicensePolarConfig.validationGraceInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> LicenseStore {
        LicenseStore(
            fileURL: url,
            client: client,
            graceInterval: grace,
            now: now,
            deviceLabel: { "Test Mac" }
        )
    }

    @Test("Activate stores a granted receipt with the returned activation id")
    func activatePersistsReceipt() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient(
            activateResult: .success(
                PolarActivation(activationId: "act-xyz", status: .granted, email: "paid@user.com", name: "Paid User")
            )
        )
        let store = makeStore(at: url, client: client)

        let receipt = try await store.activate(key: "  GARG-ABCD  ")

        #expect(client.activateCount == 1)
        #expect(receipt.key == "GARG-ABCD") // trimmed
        #expect(receipt.activationId == "act-xyz")
        #expect(receipt.email == "paid@user.com")
        #expect(receipt.status == .granted)
        #expect(store.loadCachedReceipt()?.activationId == "act-xyz")
    }

    @Test("Activation limit reached surfaces as a typed error")
    func activateLimitReached() async {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient(activateResult: .failure(.activationLimitReached))
        let store = makeStore(at: url, client: client)

        await #expect(throws: PolarLicenseError.activationLimitReached) {
            try await store.activate(key: "GARG-FULL")
        }
        #expect(store.loadCachedReceipt() == nil)
    }

    @Test("Fresh granted receipt is currently valid; stale one is not")
    func graceWindow() throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url, client: MockPolarClient(), grace: 100)

        let fresh = LicenseReceipt(
            key: "K", activationId: "A", email: nil, name: nil,
            status: .granted, activatedAt: Date(timeIntervalSince1970: 0),
            lastValidated: Date(timeIntervalSince1970: 1000)
        )
        // 50s later — within 100s grace
        #expect(store.isCurrentlyValid(fresh, at: Date(timeIntervalSince1970: 1050)))
        // 150s later — past grace
        #expect(!store.isCurrentlyValid(fresh, at: Date(timeIntervalSince1970: 1150)))
    }

    @Test("Revoked status is never currently valid even within grace")
    func revokedNotValid() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(at: url, client: MockPolarClient(), grace: 10_000)
        let revoked = LicenseReceipt(
            key: "K", activationId: "A", email: nil, name: nil,
            status: .revoked, activatedAt: Date(), lastValidated: Date()
        )
        #expect(!store.isCurrentlyValid(revoked))
    }

    @Test("Revalidate refreshes the timestamp on granted")
    func revalidateRefreshes() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1000))
        let client = MockPolarClient()
        let store = LicenseStore(
            fileURL: url, client: client,
            now: { clock.now }, deviceLabel: { "Test Mac" }
        )
        try await store.activate(key: "GARG-1")
        clock.now = Date(timeIntervalSince1970: 5000)

        let updated = try await store.revalidate()

        #expect(client.validateCount == 1)
        #expect(client.lastValidatedActivationId == "act-1")
        #expect(updated?.lastValidated == Date(timeIntervalSince1970: 5000))
    }

    @Test("Revalidate clears the cache when the server reports revoked")
    func revalidateClearsOnRevoked() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient()
        let store = makeStore(at: url, client: client)
        try await store.activate(key: "GARG-1")

        client.validateResult = .success(PolarValidation(status: .revoked, email: nil, name: nil))
        let result = try await store.revalidate()

        #expect(result == nil)
        #expect(store.loadCachedReceipt() == nil)
    }

    @Test("Revalidate clears the cache on 404 (stale activation)")
    func revalidateClearsOnNotFound() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient()
        let store = makeStore(at: url, client: client)
        try await store.activate(key: "GARG-1")

        client.validateResult = .failure(.notFound)
        let result = try await store.revalidate()

        #expect(result == nil)
        #expect(store.loadCachedReceipt() == nil)
    }

    @Test("Revalidate keeps the cache when the network is down (offline grace)")
    func revalidateKeepsCacheOffline() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient()
        let store = makeStore(at: url, client: client)
        try await store.activate(key: "GARG-1")

        client.validateResult = .failure(.network("offline"))
        await #expect(throws: PolarLicenseError.network("offline")) {
            try await store.revalidate()
        }
        // Cache survives so offline grace still applies.
        #expect(store.loadCachedReceipt() != nil)
    }

    @Test("Deactivate calls the server and clears the cache")
    func deactivateClears() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient()
        let store = makeStore(at: url, client: client)
        try await store.activate(key: "GARG-1")

        try await store.deactivate()

        #expect(client.deactivateCount == 1)
        #expect(store.loadCachedReceipt() == nil)
    }

    @Test("Deactivate still clears the cache when the server call fails")
    func deactivateClearsEvenOnError() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let client = MockPolarClient(deactivateError: .network("offline"))
        let store = makeStore(at: url, client: client)
        try await store.activate(key: "GARG-1")

        try await store.deactivate()

        #expect(store.loadCachedReceipt() == nil)
    }

    @Test("Loading from a non-existent file returns nil")
    func missingFileReturnsNil() {
        let store = makeStore(at: tempFileURL(), client: MockPolarClient())
        #expect(store.loadCachedReceipt() == nil)
    }
}
