import Foundation

/// Re-validates, immediately before a non-privileged deletion, that the path a
/// scan recorded has not had a symlink swapped into its parent chain between
/// scan (the check) and clean (the use) — the classic TOCTOU window.
///
/// `FileManager.removeItem` and Finder both follow symlinked *parent*
/// components, so an attacker able to write to a scanned directory could, in the
/// race window, redirect a delete onto a file the user never selected. The
/// root-privileged helper already rejects symlinked paths
/// (`GargantuaPrivilegedHelper/main.swift`); this gives the in-process,
/// user-owned delete path the same guarantee.
///
/// A symlink at the *leaf* is not redirected here: `removeItem` on a symlink
/// unlinks the link itself rather than its target, so legitimate symlink items
/// (e.g. broken-symlink cleanup) still delete correctly. Only an ancestor
/// redirection — the dangerous case — is rejected.
///
/// macOS firmlinks (the data/system volume split surfaced as `/private/var` vs
/// `/var`, etc.) are not symlinks; `PrivilegedRemovabilityPolicy.canonical`
/// normalizes those so they never trip the check.
public enum SymlinkSwapGuard {
    /// Returns `true` when `url`'s parent chain still resolves to itself — no
    /// symlink redirection has appeared above the leaf since scan time.
    public static func isUnchanged(_ url: URL) -> Bool {
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        let standardized = PrivilegedRemovabilityPolicy.canonical(parent.path)
        let resolved = PrivilegedRemovabilityPolicy.canonical(parent.resolvingSymlinksInPath().path)
        return standardized == resolved
    }
}
