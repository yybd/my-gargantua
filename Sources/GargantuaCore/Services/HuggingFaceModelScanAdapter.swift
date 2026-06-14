import Foundation

/// Surfaces individual Hugging Face hub repos as removable cleanup candidates.
///
/// Unlike Ollama, a repo's blobs aren't shared with other repos, so the whole
/// `<type>--<org>--<name>` directory is a safe, self-contained unit. Each result
/// is an ordinary path removal (the cache dir), routed through the normal
/// `CleanupEngine` so it goes to Trash (recoverable) — never a snapshot-only
/// delete, which would strand the blobs and overstate the space freed.
public struct HuggingFaceModelScanAdapter: ScanAdapter {
    public static let category = "ai_models"
    public static let resultIDPrefix = "huggingface-repo:"
    public static let revisionResultIDPrefix = "huggingface-revisions:"
    public static let tag = "huggingface-repo"
    public static let revisionTag = "huggingface-stale-revision"

    private let inventory: HuggingFaceCacheInventory
    private let categories: Set<String>?

    public init(inventory: HuggingFaceCacheInventory, categories: Set<String>? = nil) {
        self.inventory = inventory
        self.categories = categories
    }

    public static func loadDefaults(
        categories: Set<String>? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HuggingFaceModelScanAdapter {
        HuggingFaceModelScanAdapter(
            inventory: HuggingFaceCacheInventory.loadDefault(environment: environment, homeDirectory: homeDirectory),
            categories: categories
        )
    }

    public func scan(progress: ScanProgress?) async throws -> [ScanResult] {
        try await scan(progress: progress, observer: nil)
    }

    public func scan(
        progress: ScanProgress?,
        observer: (any ScanProgressObserving)?
    ) async throws -> [ScanResult] {
        guard categories == nil || categories?.contains(Self.category) == true else { return [] }

        let results = inventory.load().map(Self.makeResult)
            + inventory.loadStaleRevisions().map(Self.makeRevisionResult)
        for result in results {
            observer?.didEmit(ScanProgressEvent(path: result.path, outcome: .match, bytes: result.size))
        }
        return results
    }

    static func makeResult(_ repo: HuggingFaceRepo) -> ScanResult {
        let size = ByteCountFormatter.string(fromByteCount: repo.sizeBytes, countStyle: .file)
        return ScanResult(
            id: "\(resultIDPrefix)\(repo.reference)",
            name: "Hugging Face \(repo.repoType) — \(repo.repoID)",
            path: repo.cacheDirectory,
            size: repo.sizeBytes,
            safety: .review,
            confidence: 80,
            explanation: "Cached Hugging Face \(repo.repoType) \(repo.repoID) (\(size)). "
                + "Removes the whole cached repo — weights and snapshots together. "
                + "Re-downloaded on next load from the Hub.",
            source: SourceAttribution(name: "Hugging Face"),
            lastAccessed: repo.lastModified,
            category: category,
            tags: ["ai", "models", "huggingface", tag, "hf-\(repo.repoType)"],
            regenerates: true
        )
    }

    static func makeRevisionResult(_ stale: HuggingFaceStaleRevisions) -> ScanResult {
        let size = ByteCountFormatter.string(fromByteCount: stale.reclaimableBytes, countStyle: .file)
        let plural = stale.detachedRevisionCount == 1 ? "revision" : "revisions"
        return ScanResult(
            id: "\(revisionResultIDPrefix)\(stale.repoReference)",
            name: "Hugging Face \(stale.repoReference) — \(stale.detachedRevisionCount) stale \(plural)",
            path: stale.repoDirectory,
            size: stale.reclaimableBytes,
            safety: .review,
            confidence: 85,
            explanation: "\(stale.detachedRevisionCount) cached \(plural) of \(stale.repoReference) "
                + "no longer pointed to by any ref (superseded by newer pulls). "
                + "Pruning frees \(size) and keeps the current revision intact.",
            source: SourceAttribution(name: "Hugging Face"),
            lastAccessed: stale.lastModified,
            category: category,
            tags: ["ai", "models", "huggingface", revisionTag, "hf-\(stale.repoReference.split(separator: "/").first ?? "model")"],
            regenerates: true
        )
    }
}

extension ScanResult {
    /// Whether this result is a Hugging Face hub repo emitted by
    /// `HuggingFaceModelScanAdapter`. These are ordinary path removals; the flag
    /// exists for surfaces that want to label or group them.
    public var isHuggingFaceRepo: Bool {
        id.hasPrefix(HuggingFaceModelScanAdapter.resultIDPrefix)
    }

    /// Whether this result prunes stale (detached) revisions of a Hugging Face
    /// repo. The engine recomputes the exact paths to remove at delete time from
    /// `path` (the repo dir) rather than trashing it wholesale.
    public var isHuggingFaceRevisionPrune: Bool {
        id.hasPrefix(HuggingFaceModelScanAdapter.revisionResultIDPrefix)
    }
}
