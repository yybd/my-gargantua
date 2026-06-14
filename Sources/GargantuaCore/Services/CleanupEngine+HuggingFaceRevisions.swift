import Foundation

extension CleanupEngine {
    /// Prune a Hugging Face repo's detached revisions. The exact set is
    /// recomputed here (not trusted from scan time) so a `ref` that moved can't
    /// strand a still-referenced revision, then each path is trashed/deleted
    /// through the normal single-item machinery for recoverability.
    @MainActor
    func pruneHuggingFaceRevisions(item: ScanResult, method: CleanupMethod) async -> CleanupItemResult {
        guard let stale = HuggingFaceCacheInventory.staleRevisions(forRepoAt: URL(fileURLWithPath: item.path)),
              !stale.removablePaths.isEmpty else {
            // Nothing detached anymore (already pruned, or ref moved) — the
            // user's intent is satisfied.
            return CleanupItemResult(item: item, succeeded: true)
        }

        var allSucceeded = true
        var firstError: String?
        for path in stale.removablePaths {
            let url = URL(fileURLWithPath: path)
            guard fileExists(url.path) else { continue }
            let outcome = method == .delete
                ? await deleteSingle(url: url, item: item)
                : await recycleSingle(url: url, item: item)
            if !outcome.succeeded {
                allSucceeded = false
                firstError = firstError ?? outcome.error
            }
        }
        return CleanupItemResult(item: item, succeeded: allSucceeded, error: allSucceeded ? nil : firstError)
    }
}
