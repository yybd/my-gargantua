import Foundation
import Observation

@MainActor
@Observable
public final class LicenseStateModel {
    public static let shared = LicenseStateModel()

    public private(set) var state: LicenseState = .none

    private let gate: LicenseGate

    public init(gate: LicenseGate = .shared) {
        self.gate = gate
        // Kick off the first refresh so observing views don't have to wait for
        // their own .task modifier to fire — .task on a body that initially
        // resolves to EmptyView doesn't always run.
        Task { await self.refresh() }
    }

    public func refresh() async {
        state = await gate.currentState()
    }
}
