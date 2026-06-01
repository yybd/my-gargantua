import AppKit
import SwiftUI

// MARK: - Actions

extension ProcessInventoryView {
    func revealBinary(_ item: ProcessItem) {
        guard let exe = item.executablePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: exe)])
    }

    func revealPlist(_ item: ProcessItem) {
        guard let plist = item.launchSource.plistPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: plist)])
    }

    func explain(_ item: ProcessItem) {
        guard let onExplain else { return }
        onExplain(item.toScanResult())
    }

    func startSnapshot() {
        Task { await session.scan(metric: sortMetric, topN: Self.defaultTopN) }
    }

    func clearSnapshot() {
        expandedID = nil
        session.clearSnapshot()
    }

    func runAction(_ pending: PendingProcessAction) async {
        let outcome = await session.perform(
            pending.action,
            on: pending.item,
            metric: sortMetric,
            topN: Self.defaultTopN
        )
        if outcome.succeeded {
            // Successful `.removeSource` carries the plist path the receiver
            // pane should pre-select; navigation happens after the sheet has
            // already dismissed so the destination view animates in cleanly.
            if let path = outcome.routedPlistPath {
                if let onNavigateToBackgroundItems {
                    onNavigateToBackgroundItems(path)
                } else {
                    // No nav handler wired — surface a clear message so the
                    // user isn't left wondering why the sheet just dismissed.
                    lastError = "Background Items navigation is not configured. Open the Background Items pane manually to act on this source."
                }
            }
            return
        }
        if let error = outcome.error {
            lastError = error
        }
    }
}
