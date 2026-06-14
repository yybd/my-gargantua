import AppKit
import Foundation

/// Result of cleaning a single item.
public struct CleanupItemResult: Sendable {
    /// The scan result that was cleaned.
    public let item: ScanResult
    /// Whether the cleanup succeeded.
    public let succeeded: Bool
    /// The new URL (Trash location) if the item was moved successfully.
    public let trashURL: URL?
    /// Error description if the cleanup failed.
    public let error: String?

    public init(item: ScanResult, succeeded: Bool, trashURL: URL? = nil, error: String? = nil) {
        self.item = item
        self.succeeded = succeeded
        self.trashURL = trashURL
        self.error = error
    }
}

/// Aggregate result of a cleanup operation.
public struct CleanupResult: Sendable {
    /// Per-item results.
    public let itemResults: [CleanupItemResult]
    /// How the items were removed.
    public let cleanupMethod: CleanupMethod
    /// Timestamp when the cleanup completed.
    public let completedAt: Date

    public var succeededItems: [CleanupItemResult] {
        itemResults.filter(\.succeeded)
    }

    public var failedItems: [CleanupItemResult] {
        itemResults.filter { !$0.succeeded }
    }

    public var totalFreed: Int64 {
        succeededItems.reduce(Int64(0)) { $0 + $1.item.size }
    }

    public var allSucceeded: Bool {
        failedItems.isEmpty
    }

    public init(
        itemResults: [CleanupItemResult],
        cleanupMethod: CleanupMethod = .trash,
        completedAt: Date = Date()
    ) {
        self.itemResults = itemResults
        self.cleanupMethod = cleanupMethod
        self.completedAt = completedAt
    }
}

/// Removes files via the selected cleanup method and tracks per-item results.
public final class CleanupEngine: Sendable {
    /// Override the home directory used to resolve `~/.Trash`. Tests only.
    private let homeDirectory: URL
    private let trashMover: any TrashMoving
    private let protectedRootPolicy: ProtectedRootPolicy
    private let commandActionRunner: CommandActionCleanupRouter
    /// When set, items that fail removal with a permission/ownership error are
    /// retried through the root-privileged helper. Left `nil` in headless
    /// contexts (the MCP server) and tests so they never silently escalate.
    private let privilegedHelper: (any PrivilegedUninstallHelping)?
    /// Existence probe used to detect items that vanished between scan and clean
    /// (e.g. a browser that wiped its cache on quit). Injectable so tests that
    /// exercise the trash mover with synthetic paths aren't short-circuited.
    private let fileExists: @Sendable (String) -> Bool

    /// - Parameter privilegedHelper: pass `XPCPrivilegedUninstallHelper()` from
    ///   interactive flows to recover root-owned items that POSIX `EPERM`
    ///   blocked. Defaults to `nil` (no escalation).
    /// - Parameter useFinderAutomation: when `true` (the GUI default) cleanup
    ///   asks Finder to move items to Trash, falling back to the direct Trash
    ///   API. Headless callers (the MCP server) pass `false`: a background
    ///   process can't satisfy an Apple Events consent prompt, so attempting it
    ///   only spawns a doomed request before the same fallback runs anyway.
    public init(
        privilegedHelper: (any PrivilegedUninstallHelping)? = nil,
        useFinderAutomation: Bool = true
    ) {
        self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.trashMover = useFinderAutomation ? FinderFirstTrashMover() : WorkspaceTrashMover()
        self.protectedRootPolicy = .loadDefault()
        self.commandActionRunner = CommandActionCleanupRouter.production()
        self.privilegedHelper = privilegedHelper
        self.fileExists = { FileManager.default.fileExists(atPath: $0) }
    }

    /// Test-only initializer. Use the default `init()` in app code. `fileExists`
    /// defaults to "everything exists" so mover/escalation tests are unaffected;
    /// the already-gone path is exercised by passing `{ _ in false }`.
    internal init(
        homeDirectoryForTesting: URL,
        trashMover: any TrashMoving = FinderFirstTrashMover(),
        protectedRootPolicy: ProtectedRootPolicy = .loadDefault(),
        commandActionRunner: CommandActionCleanupRouter = .disabled,
        privilegedHelper: (any PrivilegedUninstallHelping)? = nil,
        fileExists: @escaping @Sendable (String) -> Bool = { _ in true }
    ) {
        self.homeDirectory = homeDirectoryForTesting
        self.trashMover = trashMover
        self.protectedRootPolicy = protectedRootPolicy
        self.commandActionRunner = commandActionRunner
        self.privilegedHelper = privilegedHelper
        self.fileExists = fileExists
    }

    /// Remove the given scan results with the selected cleanup method.
    ///
    /// Each file is handled individually so partial failures are tracked.
    /// Returns a `CleanupResult` with per-item success/failure details.
    @MainActor
    public func clean(_ items: [ScanResult], method: CleanupMethod = .trash) async -> CleanupResult {
        await clean(items, method: method, observer: nil)
    }

    /// Variant that emits a `ScanProgressEvent` per item to feed the
    /// EventHorizon console during the cleaning phase. Successful removals
    /// surface as `.match` (with bytes); failures surface as `.failed`.
    @MainActor
    public func clean(
        _ items: [ScanResult],
        method: CleanupMethod = .trash,
        observer: (any ScanProgressObserving)?
    ) async -> CleanupResult {
        var results: [CleanupItemResult] = []

        for item in items {
            // Honor cooperative cancellation between items so the user's
            // "Sever Tether" abort actually stops the loop. Items already
            // deleted stay deleted; the partial CleanupResult flows through
            // to the summary so the user can see what got cleaned.
            if Task.isCancelled { break }
            let url = URL(fileURLWithPath: item.path)
            let result = await cleanSingle(url: url, item: item, method: method)
            if let observer {
                if result.succeeded {
                    observer.didEmit(ScanProgressEvent(
                        path: item.path,
                        outcome: .match,
                        bytes: item.size
                    ))
                } else {
                    observer.didEmit(ScanProgressEvent(
                        path: item.path,
                        outcome: .failed(reason: result.error ?? "unknown error")
                    ))
                }
            }
            results.append(result)
        }

        let recovered = await escalatePermissionFailures(results, observer: observer)
        return CleanupResult(itemResults: recovered, cleanupMethod: method)
    }

    /// Retry permission-class failures through the root-privileged helper.
    ///
    /// Full Disk Access lets us read root-owned paths but not delete them; the
    /// helper (running as root) is the only path that can recycle them. No-ops
    /// when no helper was injected, so headless/test callers are unaffected.
    /// Escalation always moves to Trash even for a `.delete` request — the
    /// helper supports recycle only, and recoverable-but-trashed beats failed.
    @MainActor
    private func escalatePermissionFailures(
        _ results: [CleanupItemResult],
        observer: (any ScanProgressObserving)?
    ) async -> [CleanupItemResult] {
        guard let privilegedHelper else { return results }

        let escalatable = results.enumerated().filter { _, result in
            !result.succeeded
                && !result.item.isCommandAction
                && CleanupFailureClassifier.isElevatable(result.error)
        }
        guard !escalatable.isEmpty else { return results }

        let request = PrivilegedUninstallRequest(
            planID: UUID(),
            scanResults: escalatable.map(\.element.item)
        )
        let elevated = await privilegedHelper.movePrivilegedItemsToTrash(
            request,
            authorization: .privilegedHelperApproved
        )
        let elevatedByID = Dictionary(
            elevated.map { ($0.item.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var merged = results
        for (index, original) in escalatable {
            guard let outcome = elevatedByID[original.item.id] else { continue }
            // Keep the original permission/ownership error (so the summary's
            // classifier still routes to the right remediation prompt) but append
            // the helper's reason when it differs — otherwise a real helper-side
            // failure (rejected path, trashItem error) is invisible and
            // undiagnosable, which is exactly how the firmlink bug stayed hidden.
            let mergedError: String?
            if outcome.succeeded {
                mergedError = nil
            } else if let helperError = outcome.error,
                      let originalError = original.error,
                      helperError != originalError {
                mergedError = "\(originalError) (privileged removal also failed: \(helperError))"
            } else {
                mergedError = outcome.error ?? original.error
            }
            merged[index] = CleanupItemResult(
                item: original.item,
                succeeded: outcome.succeeded,
                trashURL: outcome.trashURL,
                error: mergedError
            )
            if outcome.succeeded {
                observer?.didEmit(ScanProgressEvent(
                    path: original.item.path,
                    outcome: .match,
                    bytes: original.item.size
                ))
            }
        }
        return merged
    }

    @MainActor
    private func cleanSingle(url: URL, item: ScanResult, method: CleanupMethod) async -> CleanupItemResult {
        // Command-action items are routed through the executor regardless of
        // the requested `method` — `path` would try to trash a string like
        // "xcrun simctl delete unavailable", which is not what the user
        // confirmed. The executor writes its own kind: command audit entry
        // with the captured tool version, exit code, and arguments.
        if item.isCommandAction {
            return commandActionRunner.run(item: item, confirmationMethod: confirmationTier(for: [item]))
        }

        // Already gone. Apps like browsers wipe and recreate their cache on quit,
        // and a path can vanish between scan and clean, so the directory the scan
        // recorded may no longer exist. The user wanted it gone and it is — count
        // it as removed instead of reporting a confusing "couldn't be removed".
        if !fileExists(url.path) {
            return CleanupItemResult(item: item, succeeded: true)
        }

        if let protectedRoot = protectedRootPolicy.protectionReason(for: url, homeDirectory: homeDirectory) {
            return CleanupItemResult(
                item: item,
                succeeded: false,
                error: "Skipped \(protectedRoot): \(url.path)"
            )
        }

        // Special case: the Trash container itself cannot be removed or
        // recycled. Empty its contents instead so "Move to Trash" and
        // "Delete Permanently" both do the right thing.
        if isTrashContainer(url) {
            return await emptyTrashContainer(item: item)
        }

        // TOCTOU guard: the path the scan recorded as a real file could have had
        // a symlink swapped into its parent chain before the user confirmed the
        // clean. Both Finder trash and `removeItem` follow symlinked parents, so
        // refuse rather than risk deleting the link's target. The privileged
        // path enforces the same rule in the helper.
        guard SymlinkSwapGuard.isUnchanged(url) else {
            return CleanupItemResult(
                item: item,
                succeeded: false,
                error: "Skipped (path now resolves through a symlink): \(url.path)"
            )
        }

        switch method {
        case .trash:
            return await recycleSingle(url: url, item: item)
        case .delete:
            return await deleteSingle(url: url, item: item)
        case .toolNative:
            return CleanupItemResult(
                item: item,
                succeeded: false,
                error: "Tool-native cleanup is not supported by CleanupEngine."
            )
        }
    }

    /// Removal attempts and the delay between them for a *transient* failure —
    /// e.g. a just-quit app whose helper process is still releasing a cache file.
    /// Permission/ownership failures are never retried (they escalate instead),
    /// so the 37-items-failed permission case adds no extra latency.
    private static let maxRemovalAttempts = 3
    private static let transientRetryDelay: UInt64 = 700_000_000 // 0.7s

    /// A failure that may clear on its own (a process releasing a handle), as
    /// opposed to a permission/ownership failure (escalates) or a missing file.
    private func isTransientRemovalFailure(_ message: String) -> Bool {
        !CleanupFailureClassifier.isElevatable(message)
            && !message.lowercased().contains("no such file")
    }

    /// Move a single URL to Trash. Finder Automation is tried first, with the
    /// direct macOS Trash API kept as a fallback for denied or failed events.
    /// Retries a transient hold (e.g. a browser's helper still releasing the
    /// cache right after the user quit it via the Quit button).
    @MainActor
    private func recycleSingle(url: URL, item: ScanResult) async -> CleanupItemResult {
        var lastError = "unknown error"
        for attempt in 1 ... Self.maxRemovalAttempts {
            do {
                let trashURL = try await trashMover.moveToTrash(url)
                return CleanupItemResult(item: item, succeeded: true, trashURL: trashURL)
            } catch {
                // Vanished mid-attempt (e.g. the app cleared it) — goal met.
                if !fileExists(url.path) {
                    return CleanupItemResult(item: item, succeeded: true)
                }
                lastError = error.localizedDescription
                if attempt < Self.maxRemovalAttempts, isTransientRemovalFailure(lastError) {
                    try? await Task.sleep(nanoseconds: Self.transientRetryDelay)
                    continue
                }
                break
            }
        }
        return CleanupItemResult(item: item, succeeded: false, error: lastError)
    }

    /// Permanently delete a single URL. Runs on a detached task so the
    /// caller's MainActor thread isn't blocked while `FileManager.removeItem`
    /// walks the directory tree — large dev caches can take several seconds
    /// per item, which froze the UI (beach ball) every time the agent's
    /// modal confirmed a "Delete Permanently" cleanup.
    private func deleteSingle(url: URL, item: ScanResult) async -> CleanupItemResult {
        let pathToRemove = url
        var lastError = "unknown error"
        for attempt in 1 ... Self.maxRemovalAttempts {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.removeItem(at: pathToRemove)
                }.value
                return CleanupItemResult(item: item, succeeded: true)
            } catch {
                if !fileExists(pathToRemove.path) {
                    return CleanupItemResult(item: item, succeeded: true)
                }
                lastError = error.localizedDescription
                if attempt < Self.maxRemovalAttempts, isTransientRemovalFailure(lastError) {
                    try? await Task.sleep(nanoseconds: Self.transientRetryDelay)
                    continue
                }
                break
            }
        }
        return CleanupItemResult(item: item, succeeded: false, error: lastError)
    }

    /// Resolves to true when `url` refers to the user's Trash directory.
    /// Both `.trash` and `.delete` operations on this URL would fail
    /// (macOS refuses to remove the Trash container), so we intercept.
    private func isTrashContainer(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        let trash = trashURL.standardizedFileURL.resolvingSymlinksInPath().path
        return target == trash
    }

    private var trashURL: URL {
        homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
    }

    /// Empty the Trash: enumerate its top-level contents and remove each.
    /// Reports aggregate success/failure on a single `CleanupItemResult`
    /// keyed to the original "Trash" scan item.
    @MainActor
    private func emptyTrashContainer(item: ScanResult) async -> CleanupItemResult {
        let fm = FileManager.default
        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(
                at: trashURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            return CleanupItemResult(
                item: item,
                succeeded: false,
                error: "Could not read Trash contents: \(error.localizedDescription)"
            )
        }

        if children.isEmpty {
            return CleanupItemResult(item: item, succeeded: true)
        }

        var failures: [(url: URL, message: String)] = []
        for child in children {
            do {
                try fm.removeItem(at: child)
            } catch {
                failures.append((child, error.localizedDescription))
            }
        }

        failures = await escalateTrashFailures(failures)

        if failures.isEmpty {
            return CleanupItemResult(item: item, succeeded: true)
        }

        let summary: String
        if failures.count == 1 {
            summary = "\(failures[0].url.lastPathComponent): \(failures[0].message)"
        } else {
            let preview = failures.prefix(3).map { $0.url.lastPathComponent }.joined(separator: ", ")
            let more = failures.count > 3 ? " and \(failures.count - 3) more" : ""
            summary = "\(failures.count) Trash items could not be removed (\(preview)\(more))"
        }
        return CleanupItemResult(item: item, succeeded: false, error: summary)
    }

    /// Root-owned items in the user's own Trash (e.g. an installer's root agent
    /// the user can't unlink) get a bounded privileged delete. The helper only
    /// removes direct children of this user's `~/.Trash`. Returns the failures
    /// that remain after escalation.
    @MainActor
    private func escalateTrashFailures(
        _ failures: [(url: URL, message: String)]
    ) async -> [(url: URL, message: String)] {
        guard let privilegedHelper, !failures.isEmpty else { return failures }
        let elevatable = failures.filter { CleanupFailureClassifier.isElevatable($0.message) }
        guard !elevatable.isEmpty else { return failures }

        let request = PrivilegedUninstallRequest(
            planID: UUID(),
            items: elevatable.map {
                PrivilegedUninstallItem(
                    id: $0.url.path,
                    path: $0.url.path,
                    category: RemnantCategory.other.rawValue,
                    size: 0,
                    operation: .deleteFromTrash
                )
            },
            invokingUserID: getuid()
        )
        let results = await privilegedHelper.movePrivilegedItemsToTrash(
            request,
            authorization: .privilegedHelperApproved
        )
        let removedPaths = Set(results.filter(\.succeeded).map(\.item.path))
        return failures.filter { !removedPaths.contains($0.url.path) }
    }
}
