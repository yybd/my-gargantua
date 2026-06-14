import Foundation
import Testing
@testable import GargantuaCore

@Suite("HuggingFaceCacheInventory")
struct HuggingFaceCacheInventoryTests {

    @Test("repo directory names decode into type + org/name")
    func repoNameParsing() {
        #expect(HuggingFaceCacheInventory.parseRepo(directoryName: "models--meta-llama--Llama-3")?.type == "model")
        #expect(HuggingFaceCacheInventory.parseRepo(directoryName: "models--meta-llama--Llama-3")?.repoID == "meta-llama/Llama-3")
        #expect(HuggingFaceCacheInventory.parseRepo(directoryName: "datasets--squad")?.type == "dataset")
        #expect(HuggingFaceCacheInventory.parseRepo(directoryName: "datasets--squad")?.repoID == "squad")
        #expect(HuggingFaceCacheInventory.parseRepo(directoryName: "spaces--user--demo")?.type == "space")
        #expect(HuggingFaceCacheInventory.parseRepo(directoryName: "not-a-repo") == nil)
    }

    @Test("repo size counts real blob bytes and ignores snapshot symlinks")
    func sizeExcludesSymlinks() throws {
        let cache = try HFFixture()
        let repo = try cache.repo("models--meta-llama--Llama-3")
        try cache.blob(repo, "aaa", bytes: 1000)
        try cache.blob(repo, "bbb", bytes: 500)
        try cache.ref(repo, "main", bytes: 40)
        try cache.snapshotSymlink(repo, revision: "rev1", file: "model.safetensors", toBlob: "aaa")
        try cache.snapshotSymlink(repo, revision: "rev1", file: "config.json", toBlob: "bbb")

        let repos = HuggingFaceCacheInventory(hubRoots: [cache.hub]).load()
        #expect(repos.count == 1)
        #expect(repos[0].reference == "model/meta-llama/Llama-3")
        // 1000 + 500 blobs + 40 ref; the two snapshot symlinks contribute nothing.
        #expect(repos[0].sizeBytes == 1540)
        #expect(
            URL(fileURLWithPath: repos[0].cacheDirectory).resolvingSymlinksInPath()
                == repo.resolvingSymlinksInPath()
        )
    }

    @Test("multiple repos are returned sorted by size descending")
    func multipleReposSorted() throws {
        let cache = try HFFixture()
        let small = try cache.repo("models--org--small")
        try cache.blob(small, "s", bytes: 100)
        let big = try cache.repo("datasets--org--big")
        try cache.blob(big, "b", bytes: 9000)

        let repos = HuggingFaceCacheInventory(hubRoots: [cache.hub]).load()
        #expect(repos.map(\.reference) == ["dataset/org/big", "model/org/small"])
    }

    @Test("HF_HUB_CACHE and HF_HOME override the default hub root")
    func resolveHubRootsHonorsEnv() {
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(
            HuggingFaceCacheInventory.resolveHubRoots(environment: ["HF_HUB_CACHE": "/tmp/hub"], homeDirectory: home)
                == [URL(fileURLWithPath: "/tmp/hub", isDirectory: true)]
        )
        #expect(
            HuggingFaceCacheInventory.resolveHubRoots(environment: ["HF_HOME": "/tmp/hf"], homeDirectory: home)
                == [URL(fileURLWithPath: "/tmp/hf/hub", isDirectory: true)]
        )
        #expect(
            HuggingFaceCacheInventory.resolveHubRoots(environment: [:], homeDirectory: home).first?.path
                == "/Users/test/.cache/huggingface/hub"
        )
    }

    @Test("missing hub cache yields no repos")
    func missingCache() throws {
        let cache = try HFFixture(createHub: false)
        #expect(HuggingFaceCacheInventory(hubRoots: [cache.hub]).load().isEmpty)
    }
}

@Suite("HuggingFaceModelScanAdapter")
struct HuggingFaceModelScanAdapterTests {

    @Test("emits one review result per repo, deletable by directory path")
    func emitsPerRepoResults() async throws {
        let cache = try HFFixture()
        let repo = try cache.repo("models--BAAI--bge-small")
        try cache.blob(repo, "w", bytes: 2048)

        let adapter = HuggingFaceModelScanAdapter(
            inventory: HuggingFaceCacheInventory(hubRoots: [cache.hub]),
            categories: [HuggingFaceModelScanAdapter.category]
        )
        let results = try await adapter.scan(progress: nil)
        let result = try #require(results.first)
        #expect(result.name == "Hugging Face model — BAAI/bge-small")
        #expect(result.safety == .review)
        #expect(result.size == 2048)
        // the whole repo dir — a normal path delete
        #expect(URL(fileURLWithPath: result.path).resolvingSymlinksInPath() == repo.resolvingSymlinksInPath())
        #expect(result.isHuggingFaceRepo)
        #expect(result.tags.contains("hf-model"))
    }

    @Test("category gate keeps Hugging Face repos out of non-AI profiles")
    func categoryGate() async throws {
        let cache = try HFFixture()
        let repo = try cache.repo("models--org--m")
        try cache.blob(repo, "w", bytes: 256)

        let adapter = HuggingFaceModelScanAdapter(
            inventory: HuggingFaceCacheInventory(hubRoots: [cache.hub]),
            categories: Set(CleanupProfile.devPurge.categories)
        )
        #expect(try await adapter.scan(progress: nil).isEmpty)
    }
}

// MARK: - Fixture

private final class HFFixture {
    let root: URL
    let hub: URL

    init(createHub: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HFCacheTests-\(UUID().uuidString)", isDirectory: true)
        hub = root.appendingPathComponent("hub", isDirectory: true)
        if createHub {
            try FileManager.default.createDirectory(at: hub, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func repo(_ name: String) throws -> URL {
        let url = hub.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        return url
    }

    func blob(_ repo: URL, _ name: String, bytes: Int) throws {
        let url = repo.appendingPathComponent("blobs/\(name)")
        try Data(repeating: 0x3, count: bytes).write(to: url)
    }

    func ref(_ repo: URL, _ name: String, bytes: Int) throws {
        let dir = repo.appendingPathComponent("refs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x4, count: bytes).write(to: dir.appendingPathComponent(name))
    }

    func snapshotSymlink(_ repo: URL, revision: String, file: String, toBlob blob: String) throws {
        let dir = repo.appendingPathComponent("snapshots/\(revision)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: dir.appendingPathComponent(file).path,
            withDestinationPath: "../../blobs/\(blob)"
        )
    }
}
