import SwiftUI

// MARK: - Filter

public enum BackgroundItemFilter: CaseIterable, Equatable {
    case all
    case review
    case safe
    case protected_
    case sensitive
    case orphaned

    var displayLabel: String {
        switch self {
        case .all: "All"
        case .review: "Review"
        case .safe: "Safe"
        case .protected_: "Protected"
        case .sensitive: "Sensitive"
        case .orphaned: "Orphaned"
        }
    }

    func apply(_ items: [BackgroundItem]) -> [BackgroundItem] {
        switch self {
        case .all: items
        case .review: items.filter { $0.safety == .review }
        case .safe: items.filter { $0.safety == .safe }
        case .protected_: items.filter { $0.safety == .protected_ }
        case .sensitive: items.filter { $0.reasons.contains(.sensitiveVendor) }
        case .orphaned: items.filter { $0.isOrphaned }
        }
    }
}

// MARK: - Pending action

/// Identifies a pending action awaiting user confirmation. Stored on the view
/// rather than the session so dismissing the sheet doesn't have to round-trip
/// through `@Observable`.
public struct PendingBackgroundItemAction: Identifiable, Equatable {
    public let item: BackgroundItem
    public let action: BackgroundItemAction
    public var id: String { "\(item.id)|\(action.rawValue)" }

    public init(item: BackgroundItem, action: BackgroundItemAction) {
        self.item = item
        self.action = action
    }
}

// MARK: - Synthetic ScanResult bridge

extension BackgroundItem {
    /// Convert to a `ScanResult` so the existing `AIExplanationController`
    /// can drive the AI fallback sheet without a parallel pipeline. This is
    /// strictly a presentation bridge — nothing in the cleanup engine ever
    /// reads a synthetic result.
    public func toScanResult() -> ScanResult {
        let bytes: Int64 = 0
        let categoryName: String = {
            switch source {
            case .userLaunchAgent, .systemLaunchAgent: "background_launch_agent"
            case .launchDaemon: "background_launch_daemon"
            case .startupItem: "background_startup_item"
            case .loginItem: "background_login_item"
            }
        }()
        let attribution = SourceAttribution(
            name: identity?.vendorDisplayName ?? identity?.bundleName ?? label,
            bundleID: identity?.bundleIdentifier,
            verifySignature: false
        )
        return ScanResult(
            id: id,
            name: displayName,
            path: plistPath ?? executablePath ?? label,
            size: bytes,
            safety: safety,
            confidence: explanationConfidence,
            explanation: explanation,
            source: attribution,
            lastAccessed: nil,
            category: categoryName,
            tags: reasons.map(\.rawValue),
            regenerates: false,
            regenerateCommand: nil
        )
    }

    /// Heuristic confidence: identity + bundle present → 90, signed but
    /// unbundled → 70, unsigned → 40, no identity → 30. Used only in the
    /// synthetic bridge; the deterministic explanation itself doesn't carry
    /// a confidence score yet.
    private var explanationConfidence: Int {
        guard let identity else { return 30 }
        if identity.bundlePath != nil, identity.vendor != .unsigned { return 90 }
        if identity.vendor == .unsigned { return 40 }
        return 70
    }
}
