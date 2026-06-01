import Foundation

/// Discovers stale or prunable linked git worktrees and emits review-gated
/// scan items.
///
/// Ported from Mole's `reclaim stale AI agent git worktrees` (tw93/Mole#985).
/// Discovery is filesystem-only — it reads each repository's
/// `.git/worktrees/<name>` admin metadata rather than shelling out to `git`,
/// so it is deterministic, testable, and works whether or not `git` is on PATH.
///
/// Only *linked* worktrees are surfaced; the primary working tree is never
/// touched. Everything is classified `.review` — a worktree can hold
/// uncommitted or unpushed work, so "stale" is never "safe".
public struct GitWorktreeScanAdapter: ScanAdapter {
    public static let resultIDPrefix = "git-worktree:"
    public static let tag = "git-worktree"
    public static let category = "dev_artifacts"

    private let policy: GitWorktreeScanPolicy
    private let categories: Set<String>?
    private let now: @Sendable () -> Date
    // FileManager isn't Sendable, but this adapter only issues read-only,
    // thread-safe queries against it (and defaults to the shared instance).
    nonisolated(unsafe) private let fileManager: FileManager

    public init(
        policy: GitWorktreeScanPolicy,
        categories: Set<String>? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        fileManager: FileManager = .default
    ) {
        self.policy = policy
        self.categories = categories
        self.now = now
        self.fileManager = fileManager
    }

    public func scan(progress: ScanProgress?) async throws -> [ScanResult] {
        guard categories == nil || categories?.contains(Self.category) == true else { return [] }
        return discoverCandidates().map(Self.makeScanResult)
    }

    /// Walks the configured roots, finds git repositories, and returns every
    /// linked worktree that is prunable or inactive past the staleness window.
    public func discoverCandidates() -> [GitWorktreeCandidate] {
        var seenWorktreePaths = Set<String>()
        var candidates: [GitWorktreeCandidate] = []

        for repo in repositories() {
            for candidate in linkedWorktrees(in: repo) {
                let key = GitWorktreeScanPolicy.normalizedPath(candidate.path)
                guard seenWorktreePaths.insert(key).inserted else { continue }
                candidates.append(candidate)
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.repositoryName != rhs.repositoryName {
                return lhs.repositoryName.localizedStandardCompare(rhs.repositoryName) == .orderedAscending
            }
            return lhs.worktreeName.localizedStandardCompare(rhs.worktreeName) == .orderedAscending
        }
    }

    // MARK: - Repository discovery

    private func repositories() -> [URL] {
        var seen = Set<String>()
        var repos: [URL] = []
        for root in policy.roots {
            for repo in collectRepositories(in: root, depth: 0)
                where seen.insert(GitWorktreeScanPolicy.normalizedPath(repo.path)).inserted {
                repos.append(repo)
            }
        }
        return repos
    }

    /// Returns repositories found at or under `dir`. A directory containing a
    /// `.git` directory is a repository; the walk stops descending there.
    private func collectRepositories(in dir: URL, depth: Int) -> [URL] {
        guard depth <= policy.maxDepth else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        if children.contains(where: { url in
            url.lastPathComponent == ".git" && isDirectory(url)
        }) {
            return [dir]
        }

        return children.flatMap { child -> [URL] in
            let name = child.lastPathComponent
            guard isDirectory(child),
                  !name.hasPrefix("."),
                  !policy.skippedDirectoryNames.contains(name) else {
                return []
            }
            return collectRepositories(in: child, depth: depth + 1)
        }
    }

    // MARK: - Worktree parsing

    private func linkedWorktrees(in repo: URL) -> [GitWorktreeCandidate] {
        let adminRoot = repo
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("worktrees", isDirectory: true)
        guard let admins = try? fileManager.contentsOfDirectory(
            at: adminRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return admins.compactMap { admin in
            guard isDirectory(admin) else { return nil }
            return candidate(repository: repo, admin: admin)
        }
    }

    private func candidate(repository: URL, admin: URL) -> GitWorktreeCandidate? {
        // A locked worktree is intentionally retained — never propose it.
        if fileManager.fileExists(atPath: admin.appendingPathComponent("locked").path) {
            return nil
        }

        guard let worktreePath = worktreePath(fromAdmin: admin) else { return nil }
        guard policy.protectionReason(for: worktreePath) == nil,
              !policy.isExcluded(path: worktreePath) else {
            return nil
        }

        let lastActivity = newestAdminTimestamp(admin: admin)
        let workingDirExists = isDirectory(URL(fileURLWithPath: worktreePath))

        let reason: GitWorktreeStaleReason
        if !workingDirExists {
            reason = .prunable
        } else if let lastActivity,
                  now().timeIntervalSince(lastActivity) >= policy.staleAfter {
            let days = Int(now().timeIntervalSince(lastActivity) / 86_400)
            reason = .inactive(days: days)
        } else {
            // Active worktree (or no timestamp evidence) — leave it alone.
            return nil
        }

        let size: Int64 = workingDirExists
            ? DirectorySizeScanner.directorySize(at: worktreePath).totalSize
            : DirectorySizeScanner.directorySize(at: admin.path).totalSize

        return GitWorktreeCandidate(
            repositoryName: repository.lastPathComponent,
            worktreeName: admin.lastPathComponent,
            path: worktreePath,
            size: size,
            lastActivity: lastActivity,
            reason: reason
        )
    }

    /// The `gitdir` admin file points at the worktree's `.git` file; the
    /// worktree directory is that file's parent.
    private func worktreePath(fromAdmin admin: URL) -> String? {
        let gitdirFile = admin.appendingPathComponent("gitdir")
        guard let raw = try? String(contentsOf: gitdirFile, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).deletingLastPathComponent().path
    }

    private func newestAdminTimestamp(admin: URL) -> Date? {
        let probes = ["HEAD", "index", "ORIG_HEAD"].map { admin.appendingPathComponent($0) } + [admin]
        return probes.compactMap { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        .max()
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Result mapping

    private static func makeScanResult(_ candidate: GitWorktreeCandidate) -> ScanResult {
        let evidence: String
        switch candidate.reason {
        case .prunable:
            evidence = "Its working directory is gone, so `git worktree prune` would drop this stale registration."
        case let .inactive(days):
            evidence = "No worktree activity in \(days) day\(days == 1 ? "" : "s")."
        }

        return ScanResult(
            id: resultIDPrefix + sanitizedID("\(candidate.repositoryName)-\(candidate.worktreeName)-\(candidate.path)"),
            name: "\(candidate.repositoryName) worktree — \(candidate.worktreeName)",
            path: candidate.path,
            size: candidate.size,
            safety: .review,
            confidence: 72,
            explanation: [
                "Linked git worktree of \(candidate.repositoryName).",
                evidence,
                "A worktree can hold uncommitted or unpushed work, so Gargantua marks this review and keeps removal behind confirmation.",
            ].joined(separator: " "),
            source: SourceAttribution(name: "Git"),
            lastAccessed: candidate.lastActivity,
            category: category,
            tags: ["developer", "git", tag].sorted(),
            regenerates: false
        )
    }

    private static func sanitizedID(_ raw: String) -> String {
        let mapped = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return String(mapped)
            .split(separator: "-")
            .joined(separator: "-")
            .lowercased()
    }
}
