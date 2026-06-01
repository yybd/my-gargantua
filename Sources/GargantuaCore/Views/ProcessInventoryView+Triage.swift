import SwiftUI

// MARK: - Suspicious triage scoring

extension ProcessInventoryView {
    func suspiciousTriageResults(_ scan: ProcessInventoryScan) -> [ScanResult] {
        scan.items.compactMap { item -> (score: Int, result: ScanResult)? in
            let triage = processTriageSignals(for: item)
            guard triage.score >= 40 else { return nil }
            return (triage.score, processTriageResult(for: item, signals: triage.signals))
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.result.name.localizedCaseInsensitiveCompare(rhs.result.name) == .orderedAscending
        }
        .prefix(6)
        .map(\.result)
    }

    func processTriageSignals(for item: ProcessItem) -> (score: Int, signals: [String]) {
        guard item.safety != .protected_ else { return (0, []) }
        let contributions = Self.triageReasonContributions(for: item)
            + Self.triageLaunchContributions(for: item)
            + Self.triagePathContributions(for: item)
            + Self.triageUsageContributions(for: item)
        return (contributions.reduce(0) { $0 + $1.points }, contributions.map(\.signal))
    }

    static func triageReasonContributions(for item: ProcessItem) -> [(points: Int, signal: String)] {
        var out: [(Int, String)] = []
        if item.reasons.contains(.unsigned) { out.append((90, "unsigned binary")) }
        if item.reasons.contains(.orphaned) { out.append((80, "orphaned launch source")) }
        if item.reasons.contains(.rootProcess) { out.append((55, "runs as root")) }
        return out
    }

    static func triageLaunchContributions(for item: ProcessItem) -> [(points: Int, signal: String)] {
        var out: [(Int, String)] = []
        switch item.launchSource {
        case .unknown: out.append((45, "unknown launch source"))
        case .childProcess: out.append((20, "child process"))
        case .userSession: out.append((15, "user-session process"))
        case .foregroundApp, .launchd: break
        }
        switch item.launchConfidence {
        case .heuristic: out.append((35, "weak launchd match"))
        case .unknown: out.append((25, "unmatched launch source"))
        case .exact, .path: break
        }
        return out
    }

    static func triagePathContributions(for item: ProcessItem) -> [(points: Int, signal: String)] {
        guard let path = item.executablePath else { return [] }
        var out: [(Int, String)] = []
        let lower = path.lowercased()
        if lower.hasPrefix("/tmp/") || lower.hasPrefix("/private/tmp/") || lower.contains("/var/folders/") {
            out.append((35, "temporary-path executable"))
        }
        if lower.contains("/downloads/") {
            out.append((20, "runs from downloads"))
        }
        return out
    }

    static func triageUsageContributions(for item: ProcessItem) -> [(points: Int, signal: String)] {
        var out: [(Int, String)] = []
        if item.cpuFraction >= 0.4 { out.append((12, "high CPU")) }
        if item.residentBytes >= 512 * 1_024 * 1_024 { out.append((8, "high memory")) }
        return out
    }

    func processTriageResult(for item: ProcessItem, signals: [String]) -> ScanResult {
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
            category: "process_triage",
            tags: base.tags + signals.map { "triage_signal:\($0.replacingOccurrences(of: " ", with: "_"))" },
            regenerates: base.regenerates,
            regenerateCommand: base.regenerateCommand
        )
    }
}
