import Foundation

/// Surfaces individual Ollama models as removable cleanup candidates.
///
/// Ollama is a managed-manifest store, so its blobs are never path-deleted (see
/// `AIModelStoreKind`). This adapter instead reconstructs each named model from
/// its manifest and emits one result per model; `CleanupEngine` routes those
/// through `OllamaModelCleanupRouter` (Ollama's own delete), not file removal.
public struct OllamaModelScanAdapter: ScanAdapter {
    public static let category = "ai_models"
    public static let resultIDPrefix = "ollama-model:"
    public static let tag = "ollama-model"

    private let inventory: OllamaModelInventory
    private let categories: Set<String>?

    public init(inventory: OllamaModelInventory, categories: Set<String>? = nil) {
        self.inventory = inventory
        self.categories = categories
    }

    public static func loadDefaults(
        categories: Set<String>? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> OllamaModelScanAdapter {
        OllamaModelScanAdapter(
            inventory: OllamaModelInventory.loadDefault(environment: environment, homeDirectory: homeDirectory),
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
        for result in results {
            observer?.didEmit(ScanProgressEvent(path: result.path, outcome: .match, bytes: result.size))
        }
        return results
    }

    static func makeResult(_ model: OllamaModelInventoryItem) -> ScanResult {
        ScanResult(
            id: "\(resultIDPrefix)\(model.reference)",
            name: "Ollama model — \(model.reference)",
            path: model.manifestPath,
            size: model.reclaimableBytes,
            safety: .review,
            confidence: 80,
            explanation: explanation(for: model),
            source: SourceAttribution(name: "Ollama", bundleID: "com.electron.ollama"),
            lastAccessed: model.lastModified,
            category: category,
            tags: ["ai", "models", "ollama", tag],
            regenerates: false,
            regenerateCommand: "ollama pull \(model.reference)"
        )
    }

    private static func explanation(for model: OllamaModelInventoryItem) -> String {
        let total = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        let freed = ByteCountFormatter.string(fromByteCount: model.reclaimableBytes, countStyle: .file)
        var lines = "Ollama model \(model.reference) uses \(total). Deleting frees \(freed)"
        if model.sharedBytes > 0 {
            let shared = ByteCountFormatter.string(fromByteCount: model.sharedBytes, countStyle: .file)
            let names = model.sharedWith.isEmpty ? "other models" : model.sharedWith.joined(separator: ", ")
            lines += "; \(shared) is shared with \(names) and stays"
        }
        lines += ". Removed through Ollama (ollama rm) — re-pull with `ollama pull \(model.reference)`."
        return lines
    }
}

extension ScanResult {
    /// Whether this result is an Ollama model emitted by `OllamaModelScanAdapter`.
    /// The engine special-cases these to route through Ollama's own delete API
    /// rather than removing the manifest path.
    public var isOllamaModel: Bool {
        id.hasPrefix(OllamaModelScanAdapter.resultIDPrefix)
    }

    /// The `name:tag` reference recovered from the result id, or nil if this
    /// isn't an Ollama model result.
    public var ollamaModelReference: String? {
        guard isOllamaModel else { return nil }
        return String(id.dropFirst(OllamaModelScanAdapter.resultIDPrefix.count))
    }
}
