import Foundation

/// One cached Hugging Face repo (model / dataset / space) in the hub cache.
///
/// The hub cache stores each repo as a self-contained `<type>--<org>--<name>`
/// directory: real weight files under `blobs/`, with `snapshots/<rev>/…`
/// holding symlinks into them. Blobs are not shared across repos, so the whole
/// directory is the safe unit of deletion and `sizeBytes` (real files only,
/// symlinks excluded) is fully reclaimable.
public struct HuggingFaceRepo: Sendable, Equatable, Identifiable {
    public let repoType: String
    public let repoID: String
    public let cacheDirectory: String
    public let sizeBytes: Int64
    public let lastModified: Date?

    public var id: String { cacheDirectory }

    /// Stable, human-facing reference, e.g. `model/meta-llama/Llama-3`.
    public var reference: String { "\(repoType)/\(repoID)" }

    public init(
        repoType: String,
        repoID: String,
        cacheDirectory: String,
        sizeBytes: Int64,
        lastModified: Date?
    ) {
        self.repoType = repoType
        self.repoID = repoID
        self.cacheDirectory = cacheDirectory
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }
}

/// Detached (stale) revisions in one cached repo: snapshot directories no `ref`
/// points at, plus the blobs that become orphaned once they're removed.
///
/// `removablePaths` is the exact set to delete — detached snapshot directories
/// and the now-unreferenced blob files — and `reclaimableBytes` is the sum of
/// those blob sizes. A blob is only listed if every revision referencing it is
/// detached, so kept revisions never lose a layer.
public struct HuggingFaceStaleRevisions: Sendable, Equatable {
    public let repoReference: String
    public let repoDirectory: String
    public let detachedRevisionCount: Int
    public let reclaimableBytes: Int64
    public let removablePaths: [String]
    public let lastModified: Date?

    public init(
        repoReference: String,
        repoDirectory: String,
        detachedRevisionCount: Int,
        reclaimableBytes: Int64,
        removablePaths: [String],
        lastModified: Date?
    ) {
        self.repoReference = repoReference
        self.repoDirectory = repoDirectory
        self.detachedRevisionCount = detachedRevisionCount
        self.reclaimableBytes = reclaimableBytes
        self.removablePaths = removablePaths
        self.lastModified = lastModified
    }
}

/// Reads the Hugging Face hub cache and reconstructs per-repo entries. Pure
/// filesystem reads — never deletes.
public struct HuggingFaceCacheInventory: Sendable {
    private let hubRoots: [URL]

    public init(hubRoots: [URL]) {
        self.hubRoots = hubRoots
    }

    /// Resolve the hub cache directory, honoring `HF_HUB_CACHE` then `HF_HOME`,
    /// falling back to `~/.cache/huggingface/hub`.
    public static func resolveHubRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        func expand(_ path: String) -> URL {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let hubCache = environment["HF_HUB_CACHE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hubCache.isEmpty {
            return [expand(hubCache)]
        }
        if let hfHome = environment["HF_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hfHome.isEmpty {
            return [expand(hfHome).appendingPathComponent("hub", isDirectory: true)]
        }
        return [homeDirectory.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)]
    }

    public static func loadDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HuggingFaceCacheInventory {
        HuggingFaceCacheInventory(
            hubRoots: resolveHubRoots(environment: environment, homeDirectory: homeDirectory)
        )
    }

    private static let typePrefixes: [(prefix: String, type: String)] = [
        ("models--", "model"),
        ("datasets--", "dataset"),
        ("spaces--", "space"),
    ]

    public func load() -> [HuggingFaceRepo] {
        let fm = FileManager.default
        var byDir: [String: HuggingFaceRepo] = [:]

        for root in hubRoots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let (type, repoID) = Self.parseRepo(directoryName: entry.lastPathComponent) else { continue }
                let key = entry.standardizedFileURL.path
                let mtime = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                byDir[key] = HuggingFaceRepo(
                    repoType: type,
                    repoID: repoID,
                    cacheDirectory: entry.path,
                    sizeBytes: Self.realFileBytes(under: entry),
                    lastModified: mtime
                )
            }
        }

        return byDir.values.sorted { lhs, rhs in
            if lhs.sizeBytes != rhs.sizeBytes { return lhs.sizeBytes > rhs.sizeBytes }
            return lhs.reference.localizedStandardCompare(rhs.reference) == .orderedAscending
        }
    }

    /// Per-repo detached-revision findings across all hub roots.
    public func loadStaleRevisions() -> [HuggingFaceStaleRevisions] {
        let fm = FileManager.default
        var byDir: [String: HuggingFaceStaleRevisions] = [:]
        for root in hubRoots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let stale = Self.staleRevisions(forRepoAt: entry) else { continue }
                byDir[entry.standardizedFileURL.path] = stale
            }
        }
        return byDir.values.sorted { lhs, rhs in
            if lhs.reclaimableBytes != rhs.reclaimableBytes { return lhs.reclaimableBytes > rhs.reclaimableBytes }
            return lhs.repoReference.localizedStandardCompare(rhs.repoReference) == .orderedAscending
        }
    }

    /// `models--meta-llama--Llama-3` -> (`model`, `meta-llama/Llama-3`).
    /// Mirrors huggingface_hub's `repo_folder_name`: type prefix, then `--`
    /// stands in for `/` in the repo id.
    static func parseRepo(directoryName: String) -> (type: String, repoID: String)? {
        for (prefix, type) in typePrefixes where directoryName.hasPrefix(prefix) {
            let repoID = String(directoryName.dropFirst(prefix.count))
                .replacingOccurrences(of: "--", with: "/")
            guard !repoID.isEmpty else { return nil }
            return (type, repoID)
        }
        return nil
    }

    /// Identify detached revisions in a repo and the blobs they alone hold.
    /// Returns nil when the repo has no detached revisions (nothing to prune).
    ///
    /// Recomputed fresh at delete time so a `ref` that moved between scan and
    /// clean (TOCTOU) can't cause a still-referenced revision to be pruned.
    static func staleRevisions(forRepoAt repoDir: URL) -> HuggingFaceStaleRevisions? {
        let fm = FileManager.default
        guard let (type, repoID) = parseRepo(directoryName: repoDir.lastPathComponent) else { return nil }

        let snapshotsDir = repoDir.appendingPathComponent("snapshots", isDirectory: true)
        let blobsDir = repoDir.appendingPathComponent("blobs", isDirectory: true)

        let revisions = ((try? fm.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        guard !revisions.isEmpty else { return nil }

        let referenced = referencedRevisions(in: repoDir.appendingPathComponent("refs", isDirectory: true))
        let detached = revisions.filter { !referenced.contains($0.lastPathComponent) }
        guard !detached.isEmpty else { return nil }
        let detachedNames = Set(detached.map(\.lastPathComponent))

        // blob name -> set of revision names whose snapshot symlinks point at it.
        var blobRefs: [String: Set<String>] = [:]
        for revision in revisions {
            for blob in blobNames(referencedBySnapshot: revision) {
                blobRefs[blob, default: []].insert(revision.lastPathComponent)
            }
        }

        // A blob is reclaimable only if every revision referencing it is detached.
        let orphanBlobs = blobRefs
            .filter { !$0.value.isEmpty && $0.value.isSubset(of: detachedNames) }
            .map(\.key)

        var removablePaths = detached.map(\.path)
        var reclaimable: Int64 = 0
        for blob in orphanBlobs {
            let url = blobsDir.appendingPathComponent(blob, isDirectory: false)
            reclaimable += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            removablePaths.append(url.path)
        }

        let mtime = (try? repoDir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return HuggingFaceStaleRevisions(
            repoReference: "\(type)/\(repoID)",
            repoDirectory: repoDir.path,
            detachedRevisionCount: detached.count,
            reclaimableBytes: reclaimable,
            removablePaths: removablePaths.sorted(),
            lastModified: mtime
        )
    }

    /// Revision hashes pointed to by any `refs/*` file (e.g. `refs/main`).
    private static func referencedRevisions(in refsDir: URL) -> Set<String> {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: refsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }
        var revisions: Set<String> = []
        for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let hash = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !hash.isEmpty { revisions.insert(hash) }
            }
        }
        return revisions
    }

    /// Blob names a snapshot directory's symlinks resolve to.
    private static func blobNames(referencedBySnapshot snapshot: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: snapshot,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return [] }
        var names: [String] = []
        for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            if let target = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                names.append((target as NSString).lastPathComponent)
            }
        }
        return names
    }

    /// Sum of real (non-symlink) file bytes in the repo tree. Snapshots are
    /// symlinks into `blobs/`, so excluding them avoids double-counting and
    /// reflects what trashing the directory actually frees.
    static func realFileBytes(under dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
