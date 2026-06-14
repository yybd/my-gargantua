import Foundation

/// Whether a scan result can actually be removed, decided at scan time so the UI
/// never invites the user to select something that will only fail on execute.
public enum Removability: Sendable, Equatable {
    /// Actionable; selectable per its safety level.
    case removable
    /// Surfaced so the user sees the reclaimable space, but not selectable and
    /// not executed. `reason` is safe to show.
    case viewOnly(reason: String)

    public var isRemovable: Bool {
        if case .removable = self { return true }
        return false
    }

    public var viewOnlyReason: String? {
        if case .viewOnly(let reason) = self { return reason }
        return nil
    }
}

/// Folds the three "can't remove" gates into one scan-time decision so they are
/// surfaced honestly instead of discovered on a failed execute:
///
/// 1. the protected-root deny-list (`ProtectedRootPolicy`, user-editable),
/// 2. the `protected` safety level (per-rule), and
/// 3. system-owned paths the privileged helper's allowlist does not cover
///    (`PrivilegedRemovabilityPolicy`, hardcoded).
///
/// See `docs/designs/2026-06-06-unified-removability.md`.
public struct RemovabilityReconciler: Sendable {
    private let protectedRoots: ProtectedRootPolicy
    private let privileged: PrivilegedRemovabilityPolicy

    public init(
        protectedRoots: ProtectedRootPolicy = .loadDefault(),
        privileged: PrivilegedRemovabilityPolicy = .shared
    ) {
        self.protectedRoots = protectedRoots
        self.privileged = privileged
    }

    public func removability(for result: ScanResult) -> Removability {
        // Command actions (e.g. `go clean -cache`), Ollama model deletions, and
        // HF revision pruning aren't plain path removals of `result.path`; the
        // allowlist/deny-list don't apply.
        if result.isCommandAction || result.isOllamaModel || result.isHuggingFaceRevisionPrune {
            return .removable
        }

        // Global deny-list wins over everything.
        if let reason = protectedRoots.protectionReason(for: URL(fileURLWithPath: result.path)) {
            return .viewOnly(reason: reason)
        }

        if result.safety == .protected_ {
            return .viewOnly(reason: "Protected — Gargantua never removes this.")
        }

        // System-owned paths (rules tag these `privileged`) are removable only
        // when the root helper's allowlist covers them. The allowlist is the
        // single authority here, shared with the helper itself.
        if result.tags.contains("privileged"),
           !privileged.allows(path: result.path, isDirectory: false) {
            return .viewOnly(
                reason: "System-owned — Gargantua surfaces the space but can't remove this safely."
            )
        }

        return .removable
    }

    /// Map keyed by `ScanResult.id` for the whole result set.
    public func map(for results: [ScanResult]) -> [String: Removability] {
        var out: [String: Removability] = [:]
        out.reserveCapacity(results.count)
        for result in results { out[result.id] = removability(for: result) }
        return out
    }
}
