import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseGate")
struct LicenseGateTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gargantua-gate-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json", isDirectory: false)
    }

    private func makeGate(
        client: MockPolarClient = MockPolarClient(),
        receiptURL: URL? = nil,
        storage: any TrialClockStorage = InMemoryTrialClockStorage(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> (LicenseGate, LicenseStore) {
        let store = LicenseStore(
            fileURL: receiptURL ?? tempFileURL(),
            client: client,
            now: now,
            deviceLabel: { "Test Mac" }
        )
        let clock = TrialClock(storage: storage, now: now)
        return (LicenseGate(store: store, clock: clock), store)
    }

    #if GARGANTUA_LICENSING
        @Test("Fresh install enters trial mode and allows destructive actions")
        func freshInstallAllowsTrial() async {
            let (gate, _) = makeGate()

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .trial(let days) = state {
                #expect(days == 14)
            } else {
                Issue.record("Expected .trial state, got \(state)")
            }
            #expect(decision == .allowed)
        }

        @Test("Elapsed trial with no license blocks destructive actions")
        func expiredTrialBlocks() async {
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)
            let (gate, _) = makeGate(storage: storage, now: { day30 })

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            #expect(state == .expired)
            #expect(decision == .blocked(reason: .trialExpired))
        }

        @Test("Activated license overrides trial expiry")
        func activatedLicenseOverridesTrial() async throws {
            let url = tempFileURL()
            defer { try? FileManager.default.removeItem(at: url) }
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)
            let client = MockPolarClient(
                activateResult: .success(
                    PolarActivation(activationId: "act-9", status: .granted, email: "paid@user.com", name: "Paid")
                )
            )
            let (gate, store) = makeGate(client: client, receiptURL: url, storage: storage, now: { day30 })
            try await store.activate(key: "GARG-PAID")

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .licensed(let email, _, _) = state {
                #expect(email == "paid@user.com")
            } else {
                Issue.record("Expected .licensed state, got \(state)")
            }
            #expect(decision == .allowed)
        }

        @Test("Past-grace cached license falls back to trial/expired")
        func pastGraceFallsBack() async throws {
            let url = tempFileURL()
            defer { try? FileManager.default.removeItem(at: url) }
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            // Trial also expired so we land on .expired, not .trial
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let activateTime = start
            let client = MockPolarClient()
            let store = LicenseStore(
                fileURL: url, client: client, graceInterval: 100,
                now: { activateTime }, deviceLabel: { "Test Mac" }
            )
            try await store.activate(key: "GARG-OLD") // lastValidated = start

            // Far past both grace window and trial
            let later = start.addingTimeInterval(60 * 24 * 60 * 60)
            let clock = TrialClock(storage: storage, now: { later })
            let lateStore = LicenseStore(
                fileURL: url, client: client, graceInterval: 100,
                now: { later }, deviceLabel: { "Test Mac" }
            )
            let gate = LicenseGate(store: lateStore, clock: clock)

            let state = await gate.currentState()
            #expect(state == .expired)
        }
    #else
        @Test("Source build always returns .licensed and allows destructive actions")
        func sourceBuildAlwaysAllows() async {
            let (gate, _) = makeGate()

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .licensed(let email, _, _) = state {
                #expect(email == "source-build@local")
            } else {
                Issue.record("Expected .licensed state in source build, got \(state)")
            }
            #expect(decision == .allowed)
        }
    #endif
}
