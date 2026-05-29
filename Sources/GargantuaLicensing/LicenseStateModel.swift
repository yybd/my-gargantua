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
        // Set initial state from cache immediately, then revalidate against the
        // server in the background. .task on a view that initially resolves to
        // EmptyView doesn't reliably fire, so seed from init.
        Task {
            await self.refresh()
            await self.revalidate()
        }
    }

    /// Fast: reads cache + trial clock, no network.
    public func refresh() async {
        state = await gate.currentState()
    }

    /// Background server check — extends offline grace, catches revocation.
    public func revalidate() async {
        await gate.revalidate()
        await refresh()
    }

    /// Paste-key activation. Network round-trip; updates state on success.
    public func activate(key: String) async -> Result<Void, PolarLicenseError> {
        let result = await gate.activate(key: key)
        await refresh()
        return result.map { _ in () }
    }

    public func deactivate() async {
        await gate.deactivate()
        await refresh()
    }
}
