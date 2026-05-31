import Foundation

/// Provenance record for the bundled rule snapshot: which `gargantua-rules`
/// commit it was reconciled against, plus the declared divergences.
///
/// Written by `Scripts/sync-rules.sh` and shipped as a bundle resource so the
/// app can show the exact upstream commit behind the rules it's running. The
/// snapshot is deliberately allowed to diverge from upstream in two bounded
/// ways — see `localOnly` and `pendingFromUpstream`.
public struct RuleSyncManifest: Codable, Sendable, Equatable {
    public struct Counts: Codable, Sendable, Equatable {
        public let cleanup: Int
        public let uninstall: Int
        public let command: Int
    }

    /// Source-of-truth repository URL.
    public let upstream: String
    /// Branch the snapshot tracks.
    public let ref: String
    /// Full commit SHA the snapshot was reconciled against.
    public let commit: String
    /// ISO date (yyyy-MM-dd) of the last sync.
    public let syncedAt: String
    /// Rule counts in the bundled snapshot at sync time.
    public let bundledRuleCounts: Counts?
    /// Manifest-relative paths authored in this repo, absent upstream, kept by sync.
    public let localOnly: [String]
    /// Paths allowed to differ from upstream pending reconciliation in either
    /// direction (upstream ahead, or bundle ahead awaiting backflow).
    public let pendingFromUpstream: [String]

    /// Abbreviated commit for compact display.
    public var shortCommit: String { String(commit.prefix(7)) }

    /// Load the manifest shipped alongside the rules. Returns `nil` for a
    /// source build that never ran the sync script.
    public static func loadBundled() -> RuleSyncManifest? {
        guard let url = Bundle.module.url(forResource: "rules-sync", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(RuleSyncManifest.self, from: data)
    }
}
