import Foundation

public enum LicenseState: Sendable, Equatable {
    case none
    case trial(daysRemaining: Int)
    case licensed(email: String, name: String, activatedAt: Date)
    case expired
}

public enum GateDecision: Sendable, Equatable {
    case allowed
    case blocked(reason: BlockReason)
}

public enum BlockReason: Sendable, Equatable {
    case trialExpired
    case noLicense
}
