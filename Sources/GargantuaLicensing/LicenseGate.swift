import Foundation

public actor LicenseGate {
    public static let shared = LicenseGate()

    private init() {}

    public func canExecuteDestructiveAction() async -> GateDecision {
        #if GARGANTUA_LICENSING
        return .allowed
        #else
        return .allowed
        #endif
    }

    public func currentState() async -> LicenseState {
        #if GARGANTUA_LICENSING
        return .trial(daysRemaining: 14)
        #else
        return .licensed(email: "source-build@local", name: "Source Build", activatedAt: Date(timeIntervalSince1970: 0))
        #endif
    }
}
