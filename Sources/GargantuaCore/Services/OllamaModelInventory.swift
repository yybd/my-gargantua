import Foundation

/// One named Ollama model (`name:tag`) reconstructed from its on-disk manifest.
///
/// Ollama stores a model as a manifest plus content-addressed blobs, and blobs
/// are shared across models (common base layers). `reclaimableBytes` therefore
/// counts only the blobs this model alone references — deleting it frees that
/// much, while `sharedBytes` stays behind for the models named in `sharedWith`.
public struct OllamaModelInventoryItem: Sendable, Equatable, Identifiable {
    public let reference: String
    public let manifestPath: String
    public let blobDigests: [String]
    public let totalBytes: Int64
    public let reclaimableBytes: Int64
    public let sharedWith: [String]
    public let lastModified: Date?

    public var id: String { reference }
    public var sharedBytes: Int64 { max(0, totalBytes - reclaimableBytes) }

    public init(
        reference: String,
        manifestPath: String,
        blobDigests: [String],
        totalBytes: Int64,
        reclaimableBytes: Int64,
        sharedWith: [String],
        lastModified: Date?
    ) {
        self.reference = reference
        self.manifestPath = manifestPath
        self.blobDigests = blobDigests
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
        self.sharedWith = sharedWith
        self.lastModified = lastModified
    }
}

/// Reads the Ollama model store and reconstructs the named-model graph with
/// shared-blob reference counting. Pure filesystem reads — never deletes.
public struct OllamaModelInventory: Sendable {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Resolve the models root: `OLLAMA_MODELS` if set, else `~/.ollama/models`.
    public static func resolveRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment["OLLAMA_MODELS"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".ollama/models", isDirectory: true)
    }

    public static func loadDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> OllamaModelInventory {
        OllamaModelInventory(root: resolveRoot(environment: environment, homeDirectory: homeDirectory))
    }

    public func load() -> [OllamaModelInventoryItem] {
        let manifestsDir = root.appendingPathComponent("manifests", isDirectory: true)
        let blobsDir = root.appendingPathComponent("blobs", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestsDir.path) else { return [] }

        // Parse every manifest into (reference, digests, mtime).
        let parsed = manifestFiles(under: manifestsDir).compactMap { url -> ParsedManifest? in
            guard let reference = Self.reference(forManifest: url, manifestsRoot: manifestsDir),
                  let digests = Self.digests(inManifestAt: url) else { return nil }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return ParsedManifest(reference: reference, manifestPath: url.path, digests: digests, lastModified: mtime)
        }

        // Map blob digest -> on-disk size, and digest -> referencing model count.
        let blobSizes = Self.blobSizes(forDigests: Set(parsed.flatMap(\.digests)), blobsDir: blobsDir)
        var refCount: [String: Int] = [:]
        for manifest in parsed {
            for digest in Set(manifest.digests) { refCount[digest, default: 0] += 1 }
        }

        return parsed.map { manifest in
            let digests = Array(Set(manifest.digests)).sorted()
            let total = digests.reduce(Int64(0)) { $0 + (blobSizes[$1] ?? 0) }
            let reclaimable = digests
                .filter { refCount[$0] == 1 }
                .reduce(Int64(0)) { $0 + (blobSizes[$1] ?? 0) }
            let sharedWith = parsed
                .filter { other in
                    other.reference != manifest.reference
                        && !Set(other.digests).isDisjoint(with: Set(manifest.digests))
                }
                .map(\.reference)
                .sorted()
            return OllamaModelInventoryItem(
                reference: manifest.reference,
                manifestPath: manifest.manifestPath,
                blobDigests: digests,
                totalBytes: total,
                reclaimableBytes: reclaimable,
                sharedWith: Array(Set(sharedWith)).sorted(),
                lastModified: manifest.lastModified
            )
        }
        .sorted { lhs, rhs in
            if lhs.reclaimableBytes != rhs.reclaimableBytes { return lhs.reclaimableBytes > rhs.reclaimableBytes }
            return lhs.reference.localizedStandardCompare(rhs.reference) == .orderedAscending
        }
    }
}

private extension OllamaModelInventory {
    struct ParsedManifest {
        let reference: String
        let manifestPath: String
        let digests: [String]
        let lastModified: Date?
    }

    func manifestFiles(under dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator
            where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files.append(url)
        }
        return files
    }

    /// Derive the `name:tag` reference from a manifest path under the manifests
    /// root: `<host>/<namespace>/<name…>/<tag>`. Drops the default registry and
    /// `library` namespace so library models read as `llama3:8b`.
    static func reference(forManifest url: URL, manifestsRoot: URL) -> String? {
        let rootComponents = manifestsRoot.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count + 1 else { return nil }
        var rel = Array(fileComponents.dropFirst(rootComponents.count))
        guard rel.count >= 2 else { return nil }
        let tag = rel.removeLast()
        if rel.first == "registry.ollama.ai" { rel.removeFirst() }
        if rel.first == "library" { rel.removeFirst() }
        guard !rel.isEmpty else { return nil }
        return "\(rel.joined(separator: "/")):\(tag)"
    }

    /// Collect the config + layer blob digests referenced by a manifest JSON.
    static func digests(inManifestAt url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(OllamaManifestJSON.self, from: data) else { return nil }
        var digests: [String] = []
        if let config = manifest.config?.digest { digests.append(config) }
        digests.append(contentsOf: manifest.layers.map(\.digest))
        return digests
    }

    static func blobSizes(forDigests digests: Set<String>, blobsDir: URL) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for digest in digests {
            let fileName = digest.replacingOccurrences(of: ":", with: "-")
            let blobURL = blobsDir.appendingPathComponent(fileName, isDirectory: false)
            let size = (try? blobURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            sizes[digest] = Int64(size)
        }
        return sizes
    }
}

/// The subset of an Ollama (OCI-style) manifest we read: config + layer digests.
private struct OllamaManifestJSON: Decodable {
    struct Descriptor: Decodable {
        let digest: String
    }
    let config: Descriptor?
    let layers: [Descriptor]
}
