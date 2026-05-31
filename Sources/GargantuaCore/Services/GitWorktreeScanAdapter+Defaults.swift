import Foundation

extension GitWorktreeScanAdapter {
    /// Common locations where developers keep checkouts. Combined with any
    /// user-configured scan roots and filtered to existing directories so the
    /// repo walk never wanders into the whole home folder.
    public static func defaultRoots(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        scanRoots: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> [URL] {
        let common = [
            "Developer", "Projects", "Code", "code", "src", "work",
            "git", "repos", "Documents/GitHub", "Documents/Projects",
        ].map { homeDirectory.appendingPathComponent($0, isDirectory: true) }

        var seen = Set<String>()
        return ((scanRoots ?? []) + common).filter { url in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return false
            }
            return seen.insert(GitWorktreeScanPolicy.normalizedPath(url.path)).inserted
        }
    }

    public static func loadDefaults(
        categories: Set<String>? = nil,
        scanRoots: [URL]? = nil,
        excludedPaths: Set<String> = [],
        protectedRoots: ProtectedRootPolicy = .loadDefault()
    ) -> GitWorktreeScanAdapter {
        GitWorktreeScanAdapter(
            policy: GitWorktreeScanPolicy(
                roots: defaultRoots(scanRoots: scanRoots),
                excludedPaths: excludedPaths,
                protectedRoots: protectedRoots
            ),
            categories: categories
        )
    }
}
