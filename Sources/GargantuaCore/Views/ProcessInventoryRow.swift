import AppKit
import SwiftUI

// Single row in the Process Inventory pane.
//
// Mirrors `BackgroundItemRow`'s layout: 3pt safety bar on the leading edge,
// safety-tinted background, leading-aligned label + explanation + path, with
// metrics rendered as compact monospaced badges in the trailing slot. The
// expanded section pulls in the full identity / signature / launch-source
// detail; both halves share state so SwiftUI keeps the toggle smooth.
//
// Section builders live in `ProcessInventoryRow+Sections`; `isHovered` is
// internal (not private) so that extension can reach it.
public struct ProcessInventoryRow: View {
    public let item: ProcessItem
    public let isExpanded: Bool
    public let isBusy: Bool
    public let onToggleExpand: () -> Void
    public let onRevealBinary: (() -> Void)?
    public let onRevealPlist: (() -> Void)?
    public let onExplain: (() -> Void)?
    public let onAction: ((ProcessAction) -> Void)?

    @State var isHovered = false

    public init(
        item: ProcessItem,
        isExpanded: Bool,
        isBusy: Bool = false,
        onToggleExpand: @escaping () -> Void,
        onRevealBinary: (() -> Void)? = nil,
        onRevealPlist: (() -> Void)? = nil,
        onExplain: (() -> Void)? = nil,
        onAction: ((ProcessAction) -> Void)? = nil
    ) {
        self.item = item
        self.isExpanded = isExpanded
        self.isBusy = isBusy
        self.onToggleExpand = onToggleExpand
        self.onRevealBinary = onRevealBinary
        self.onRevealPlist = onRevealPlist
        self.onExplain = onExplain
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedHeader
            if isExpanded {
                expandedDetail
            }
        }
        .background {
            RoundedRectangle(cornerRadius: GargantuaRadius.medium)
                .fill(safetyTint)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(safetyColor)
                        .frame(width: 3)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: GargantuaRadius.medium,
                                bottomLeadingRadius: GargantuaRadius.medium,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: GargantuaRadius.medium)
                .stroke(GargantuaColors.borderSoft, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
}
