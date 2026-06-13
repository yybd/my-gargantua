import Foundation
import Testing
@testable import GargantuaCore

@Suite("SymlinkSwapGuard")
struct SymlinkSwapGuardTests {

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("symlink-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("A real file under a real directory passes")
    func realPathPasses() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("cache.bin")
        try Data("x".utf8).write(to: file)

        #expect(SymlinkSwapGuard.isUnchanged(file))
    }

    @Test("A symlinked parent directory is rejected")
    func symlinkedParentRejected() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // real/cache.bin is the scanned target; `link` is a symlink to `real`.
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("cache.bin"))

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        // Deleting through the symlinked parent must be refused.
        let throughLink = link.appendingPathComponent("cache.bin")
        #expect(!SymlinkSwapGuard.isUnchanged(throughLink))
    }

    @Test("A symlink at the leaf still passes (removeItem unlinks the link, not its target)")
    func symlinkLeafPasses() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("target.bin")
        try Data("x".utf8).write(to: target)

        let leafLink = dir.appendingPathComponent("leaf")
        try FileManager.default.createSymbolicLink(at: leafLink, withDestinationURL: target)

        #expect(SymlinkSwapGuard.isUnchanged(leafLink))
    }
}
