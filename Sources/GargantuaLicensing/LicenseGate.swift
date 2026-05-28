import Foundation

public actor LicenseGate {
    public static let shared = LicenseGate.makeDefault()

    private let store: LicenseStore
    private let clock: TrialClock

    public init(store: LicenseStore, clock: TrialClock) {
        self.store = store
        self.clock = clock
    }

    public static func makeDefault() -> LicenseGate {
        LicenseGate(
            store: LicenseStore(),
            clock: TrialClock()
        )
    }

    public func canExecuteDestructiveAction() async -> GateDecision {
        switch await currentState() {
        case .licensed:
            return .allowed
        case .trial(let days) where days > 0:
            return .allowed
        case .trial, .expired:
            return .blocked(reason: .trialExpired)
        case .none:
            return .blocked(reason: .noLicense)
        }
    }

    public func currentState() async -> LicenseState {
        #if GARGANTUA_LICENSING
            if let receipt = store.loadValidReceipt() {
                return .licensed(
                    email: receipt.email,
                    name: receipt.name,
                    activatedAt: receipt.activatedAt
                )
            }
            let days = clock.daysRemaining()
            if days > 0 {
                return .trial(daysRemaining: days)
            }
            return .expired
        #else
            return .licensed(
                email: "source-build@local",
                name: "Source Build",
                activatedAt: .distantPast
            )
        #endif
    }
}
