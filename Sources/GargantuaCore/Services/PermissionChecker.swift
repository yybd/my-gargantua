import CoreServices
import Foundation
import OSLog

/// Whether Gargantua may send Apple Events to Finder.
///
/// `notDetermined` means the user has never been asked — the only way to move
/// past it (and to make Gargantua appear in System Settings ▸ Privacy &
/// Security ▸ Automation) is to attempt the event with `prompt: true`.
public enum AutomationPermission: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// Checks macOS TCC permissions required by Gargantua.
public enum PermissionChecker: Sendable {
    private static let logger = Logger(subsystem: "com.gargantua.core", category: "PermissionChecker")

    /// Whether the app has Full Disk Access.
    ///
    /// Probes a TCC-protected path that is only readable with FDA granted.
    /// Returns `false` if the path is unreadable (permission denied) or
    /// if the file doesn't exist (shouldn't happen on a normal macOS install).
    public static var hasFullDiskAccess: Bool {
        hasFullDiskAccess(
            probing: "/Library/Application Support/com.apple.TCC/TCC.db",
            isReadable: FileManager.default.isReadableFile(atPath:)
        )
    }

    /// Testable FDA probe used by `hasFullDiskAccess`.
    public static func hasFullDiskAccess(
        probing path: String,
        isReadable: (String) -> Bool
    ) -> Bool {
        isReadable(path)
    }

    /// Bundle identifier of Finder — the Apple Events target Gargantua uses for
    /// Finder-first cleanup.
    static let finderBundleID = "com.apple.finder"

    /// Resolves whether Gargantua may control Finder via Apple Events.
    ///
    /// When `prompt` is `true` and the status is undetermined, macOS shows the
    /// Automation consent dialog and registers Gargantua under System Settings ▸
    /// Privacy & Security ▸ Automation. That pane has no "+" button; an app only
    /// appears there after it attempts to send an event — which is exactly what
    /// this call does. Blocks while the prompt is on screen, so callers should
    /// invoke it off the main thread when `prompt` is `true`.
    @discardableResult
    public static func finderAutomationPermission(prompt: Bool) -> AutomationPermission {
        finderAutomationPermission(prompt: prompt, determine: determineFinderPermission)
    }

    /// Testable mapping from the raw `AEDeterminePermissionToAutomateTarget`
    /// status to `AutomationPermission`.
    static func finderAutomationPermission(
        prompt: Bool,
        determine: (Bool) -> OSStatus
    ) -> AutomationPermission {
        switch determine(prompt) {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(procNotFound):
            // Finder isn't running, so we can't determine consent yet. Expected
            // and recoverable — don't log, just stay undetermined.
            return .notDetermined
        case let other:
            // Genuinely unexpected. Mapping to undetermined is the safe default
            // (we can't conclude denial), but surface it so a status that should
            // be handled doesn't silently masquerade as "not asked yet".
            logger.error("Unexpected AEDeterminePermissionToAutomateTarget status: \(other, privacy: .public)")
            return .notDetermined
        }
    }

    private static func determineFinderPermission(_ askUserIfNeeded: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let createStatus = finderBundleID.withCString { cString in
            OSStatus(AECreateDesc(typeApplicationBundleID, cString, strlen(cString), &target))
        }
        guard createStatus == noErr else { return createStatus }
        defer { AEDisposeDesc(&target) }

        return AEDeterminePermissionToAutomateTarget(
            &target,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
    }
}
