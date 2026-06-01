import Foundation
import Testing
@testable import GargantuaCore

@Suite("DevArtifactDetection")
struct DevArtifactDetectionTests {
    /// Build an isolated temp scan root, run `body` with it, and tear it down.
    private func withTempRoot(_ body: (URL) async throws -> Void) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("dev-artifact-detection-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try await body(root)
    }

    private func touch(_ url: URL) throws {
        try Data().write(to: url)
    }

    @Test("cross-cutting buckets are always seeded")
    func crossCuttingDefaults() {
        #expect(DevArtifactDetection.alwaysSelectedCrossCutting.contains("build_cache"))
        #expect(DevArtifactDetection.alwaysSelectedCrossCutting.contains("ai_models"))
        #expect(DevArtifactDetection.alwaysSelectedCrossCutting.contains("logs"))
    }

    @Test("a top-level name marker flips its ecosystem on")
    func detectsTopLevelNameMarker() async throws {
        try await withTempRoot { root in
            try touch(root.appendingPathComponent("package.json"))

            let detected = await DevArtifactDetection.detectEcosystems(in: [root])
            #expect(detected.contains("node"))
        }
    }

    @Test("a suffix marker one directory deep flips its ecosystem on")
    func detectsNestedSuffixMarker() async throws {
        try await withTempRoot { root in
            let fm = FileManager.default
            let project = root.appendingPathComponent("MyApp", isDirectory: true)
            try fm.createDirectory(at: project, withIntermediateDirectories: true)
            // .xcodeproj is a suffix marker for the xcode ecosystem.
            try fm.createDirectory(
                at: project.appendingPathComponent("MyApp.xcodeproj", isDirectory: true),
                withIntermediateDirectories: true
            )

            let detected = await DevArtifactDetection.detectEcosystems(in: [root])
            #expect(detected.contains("xcode"))
        }
    }

    @Test("multiple ecosystems in sibling projects are all detected")
    func detectsMultipleEcosystems() async throws {
        try await withTempRoot { root in
            let fm = FileManager.default
            let nodeProj = root.appendingPathComponent("web", isDirectory: true)
            let rustProj = root.appendingPathComponent("cli", isDirectory: true)
            try fm.createDirectory(at: nodeProj, withIntermediateDirectories: true)
            try fm.createDirectory(at: rustProj, withIntermediateDirectories: true)
            try touch(nodeProj.appendingPathComponent("yarn.lock"))
            try touch(rustProj.appendingPathComponent("Cargo.toml"))

            let detected = await DevArtifactDetection.detectEcosystems(in: [root])
            #expect(detected.contains("node"))
            #expect(detected.contains("rust"))
        }
    }

    @Test("an empty tree detects no project ecosystems")
    func emptyTreeDetectsNothing() async throws {
        try await withTempRoot { root in
            let detected = await DevArtifactDetection.detectEcosystems(in: [root])
            // System-level buckets (homebrew/docker) may be present on the host,
            // but no project-tree ecosystems should be flagged for an empty dir.
            #expect(!detected.contains("node"))
            #expect(!detected.contains("rust"))
            #expect(!detected.contains("python"))
            #expect(!detected.contains("go"))
        }
    }
}
