import Foundation
import Testing
@testable import GargantuaCore

@Suite("GitWorktreeScanAdapter")
struct GitWorktreeScanAdapterTests {
    // A fixed "now" so staleness math is deterministic.
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)
    private static let day: TimeInterval = 86_400

    @Test("prunable worktree (working dir gone) surfaces as review")
    func prunableWorktreeSurfaces() async throws {
        let fixture = try FixtureTree()
        let repo = try fixture.makeRepo("acme")
        // gitdir points at a worktree path that does not exist on disk.
        try fixture.addWorktree(repo: repo, name: "agent-feature", worktreePath: fixture.root.appendingPathComponent("gone/agent-feature"), createWorkingDir: false, headAge: 2 * Self.day)

        let results = try await Self.makeAdapter(fixture).scan(progress: nil)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.safety == .review)
        #expect(result.category == "dev_artifacts")
        #expect(result.tags.contains("git-worktree"))
        #expect(result.explanation.contains("git worktree prune"))
        #expect(result.name == "acme worktree — agent-feature")
    }

    @Test("inactive worktree past the staleness window surfaces as review")
    func inactiveWorktreeSurfaces() async throws {
        let fixture = try FixtureTree()
        let repo = try fixture.makeRepo("acme")
        let wt = fixture.root.appendingPathComponent("wt/old-feature")
        try fixture.addWorktree(repo: repo, name: "old-feature", worktreePath: wt, createWorkingDir: true, headAge: 30 * Self.day)

        let results = try await Self.makeAdapter(fixture).scan(progress: nil)

        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.safety == .review)
        #expect(result.explanation.contains("No worktree activity in 30 days"))
    }

    @Test("active worktree within the window is left alone")
    func activeWorktreeIgnored() async throws {
        let fixture = try FixtureTree()
        let repo = try fixture.makeRepo("acme")
        let wt = fixture.root.appendingPathComponent("wt/live-feature")
        try fixture.addWorktree(repo: repo, name: "live-feature", worktreePath: wt, createWorkingDir: true, headAge: 1 * Self.day)

        let results = try await Self.makeAdapter(fixture).scan(progress: nil)

        #expect(results.isEmpty)
    }

    @Test("locked worktree is never proposed")
    func lockedWorktreeIgnored() async throws {
        let fixture = try FixtureTree()
        let repo = try fixture.makeRepo("acme")
        try fixture.addWorktree(repo: repo, name: "locked-feature", worktreePath: fixture.root.appendingPathComponent("gone/locked-feature"), createWorkingDir: false, headAge: 90 * Self.day, locked: true)

        let results = try await Self.makeAdapter(fixture).scan(progress: nil)

        #expect(results.isEmpty)
    }

    @Test("worktree under a protected root is skipped")
    func protectedWorktreeSkipped() async throws {
        let fixture = try FixtureTree()
        let repo = try fixture.makeRepo("acme")
        let wt = fixture.root.appendingPathComponent("protected/feature")
        try fixture.addWorktree(repo: repo, name: "feature", worktreePath: wt, createWorkingDir: true, headAge: 60 * Self.day)

        let policy = GitWorktreeScanPolicy(
            roots: [fixture.root],
            staleAfter: 7 * Self.day,
            protectedRoots: ProtectedRootPolicy(entries: [
                ProtectedRootEntry(path: wt.path, reason: "test-protected", source: .user),
            ])
        )
        let adapter = GitWorktreeScanAdapter(policy: policy, categories: ["dev_artifacts"], now: { Self.now })

        let results = try await adapter.scan(progress: nil)
        #expect(results.isEmpty)
    }

    @Test("category gate excludes the adapter when dev_artifacts is absent")
    func categoryGate() async throws {
        let fixture = try FixtureTree()
        let repo = try fixture.makeRepo("acme")
        try fixture.addWorktree(repo: repo, name: "feature", worktreePath: fixture.root.appendingPathComponent("gone/feature"), createWorkingDir: false, headAge: 30 * Self.day)

        let policy = GitWorktreeScanPolicy(roots: [fixture.root], staleAfter: 7 * Self.day)
        let adapter = GitWorktreeScanAdapter(policy: policy, categories: ["browser_cache"], now: { Self.now })

        let results = try await adapter.scan(progress: nil)
        #expect(results.isEmpty)
    }

    // MARK: - Helpers

    private static func makeAdapter(_ fixture: FixtureTree) -> GitWorktreeScanAdapter {
        GitWorktreeScanAdapter(
            policy: GitWorktreeScanPolicy(roots: [fixture.root], staleAfter: 7 * day),
            categories: ["dev_artifacts"],
            now: { now }
        )
    }

    private final class FixtureTree {
        let root: URL
        private let fm = FileManager.default

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("GitWorktreeScanAdapterTests-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? fm.removeItem(at: root) }

        /// Creates `<root>/<name>/.git/worktrees` and returns the repo URL.
        func makeRepo(_ name: String) throws -> URL {
            let repo = root.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(
                at: repo.appendingPathComponent(".git/worktrees", isDirectory: true),
                withIntermediateDirectories: true
            )
            return repo
        }

        /// Registers a linked worktree admin dir under the repo, mirroring how
        /// `git worktree add` lays out `.git/worktrees/<name>`.
        func addWorktree(
            repo: URL,
            name: String,
            worktreePath: URL,
            createWorkingDir: Bool,
            headAge: TimeInterval,
            locked: Bool = false
        ) throws {
            let admin = repo.appendingPathComponent(".git/worktrees/\(name)", isDirectory: true)
            try fm.createDirectory(at: admin, withIntermediateDirectories: true)

            // gitdir points at the worktree's `.git` file; parent is the worktree.
            let gitdirTarget = worktreePath.appendingPathComponent(".git").path + "\n"
            try gitdirTarget.write(to: admin.appendingPathComponent("gitdir"), atomically: true, encoding: .utf8)

            let head = admin.appendingPathComponent("HEAD")
            try "ref: refs/heads/\(name)\n".write(to: head, atomically: true, encoding: .utf8)
            let headDate = GitWorktreeScanAdapterTests.now.addingTimeInterval(-headAge)
            try fm.setAttributes([.modificationDate: headDate], ofItemAtPath: head.path)

            if locked {
                try "".write(to: admin.appendingPathComponent("locked"), atomically: true, encoding: .utf8)
            }
            if createWorkingDir {
                try fm.createDirectory(at: worktreePath, withIntermediateDirectories: true)
                try Data(repeating: 0x1, count: 64).write(to: worktreePath.appendingPathComponent("file.txt"))
            }
        }
    }
}
