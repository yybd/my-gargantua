import SwiftUI

// MARK: - Pending action

/// Identifies a pending action awaiting user confirmation. Stored on the view
/// rather than the session so dismissing the sheet doesn't have to round-trip
/// through `@Observable`.
public struct PendingProcessAction: Identifiable, Equatable {
    public let item: ProcessItem
    public let action: ProcessAction
    public var id: String { "\(item.id)|\(action.rawValue)" }

    public init(item: ProcessItem, action: ProcessAction) {
        self.item = item
        self.action = action
    }
}

// MARK: - Filter

public enum ProcessSafetyFilter: CaseIterable, Equatable {
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

    func apply(_ items: [ProcessItem]) -> [ProcessItem] {
        switch self {
        case .all: items
        case .review: items.filter { $0.safety == .review }
        case .safe: items.filter { $0.safety == .safe }
        case .protected_: items.filter { $0.safety == .protected_ }
        case .sensitive: items.filter { $0.reasons.contains(.sensitiveVendor) }
        case .orphaned: items.filter { $0.reasons.contains(.orphaned) }
        }
    }
}
