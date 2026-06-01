import SwiftUI

// MARK: - Suspicious triage scoring

extension BackgroundItemsView {
    func suspiciousTriageResults(_ scan: BackgroundItemScan) -> [ScanResult] {
        scan.items.compactMap { item -> (score: Int, result: ScanResult)? in
            let triage = backgroundItemTriageSignals(for: item)
            guard triage.score >= 45 else { return nil }
            return (triage.score, backgroundItemTriageResult(for: item, signals: triage.signals))
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.result.name.localizedCaseInsensitiveCompare(rhs.result.name) == .orderedAscending
        }
        .prefix(6)
        .map(\.result)
    }

    func backgroundItemTriageSignals(for item: BackgroundItem) -> (score: Int, signals: [String]) {
        guard item.safety != .protected_ else { return (0, []) }
        let contributions = Self.bgTriageReasonContributions(for: item)
            + Self.bgTriageSourceContributions(for: item)
            + Self.bgTriageIdentityContributions(for: item)
            + Self.bgTriagePathContributions(for: item)
        return (contributions.reduce(0) { $0 + $1.points }, contributions.map(\.signal))
    }

    static func bgTriageReasonContributions(for item: BackgroundItem) -> [(points: Int, signal: String)] {
        var out: [(Int, String)] = []
        if item.reasons.contains(.unsigned) { out.append((90, "unsigned binary")) }
        if item.reasons.contains(.orphaned) { out.append((80, "orphaned executable")) }
        if item.reasons.contains(.orphanedVendor) { out.append((70, "orphaned vendor")) }
        if item.reasons.contains(.listensForRequests) { out.append((25, "listens for requests")) }
        if item.reasons.contains(.persistentlyRunning) { out.append((20, "persistent at boot or login")) }
        return out
    }

    static func bgTriageSourceContributions(for item: BackgroundItem) -> [(points: Int, signal: String)] {
        switch item.source {
        case .startupItem: return [(45, "legacy startup item")]
        case .launchDaemon: return [(30, "runs as launch daemon")]
        default: return []
        }
    }

    static func bgTriageIdentityContributions(for item: BackgroundItem) -> [(points: Int, signal: String)] {
        item.identity == nil ? [(20, "no resolved identity")] : []
    }

    static func bgTriagePathContributions(for item: BackgroundItem) -> [(points: Int, signal: String)] {
        guard let path = item.executablePath ?? item.plistPath else { return [] }
        var out: [(Int, String)] = []
        let lower = path.lowercased()
        if lower.hasPrefix("/tmp/") || lower.hasPrefix("/private/tmp/") || lower.contains("/var/folders/") {
            out.append((35, "temporary-path item"))
        }
        if lower.contains("/downloads/") {
            out.append((20, "runs from downloads"))
        }
        return out
    }

    func backgroundItemTriageResult(for item: BackgroundItem, signals: [String]) -> ScanResult {
        let base = item.toScanResult()
        let readableSignals = signals.joined(separator: ", ")
        return ScanResult(
            id: "triage:\(base.id)",
            name: base.name,
            path: base.path,
            size: base.size,
            safety: base.safety,
            confidence: base.confidence,
            explanation: "Triage signals: \(readableSignals). \(base.explanation)",
            source: base.source,
            lastAccessed: base.lastAccessed,
            category: "background_item_triage",
            tags: base.tags + signals.map { "triage_signal:\($0.replacingOccurrences(of: " ", with: "_"))" },
            regenerates: base.regenerates,
            regenerateCommand: base.regenerateCommand
        )
    }
}
