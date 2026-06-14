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
