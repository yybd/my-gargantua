import Foundation
import Testing
@testable import GargantuaCore

@Suite("DuplicateFinderContainerView state derivation")
struct DuplicateFinderContainerStateTests {

    private static func makeResult(id: String) -> ScanResult {
        ScanResult(
            id: id,
            name: id,
            path: "/tmp/\(id)",
            size: 1,
            safety: .review,
            confidence: 50,
            explanation: "test",
            source: SourceAttribution(name: "DuplicateFinderContainerStateTests"),
            category: "duplicate_files"
        )
    }

    @Test("Empty results with recorded errors surface as .error — silent fclones failures are visible")
    func emptyResultsPlusErrorsBecomesError() {
        let state = DuplicateFinderContainerState.deriveScanState(
            results: [],
            errors: ["fclones exit 1: timed out"]
        )

        guard case .error(let message) = state else {
            Issue.record("Expected .error, got \(state)")
            return
        }
        #expect(message.contains("timed out"))
    }

    @Test("Empty results with no errors is a legitimate \"no duplicates\" outcome")
    func emptyResultsNoErrorsBecomesResults() {
        let state = DuplicateFinderContainerState.deriveScanState(
            results: [],
            errors: []
        )

        guard case .results(let results) = state else {
            Issue.record("Expected .results, got \(state)")
            return
        }
        #expect(results.isEmpty)
    }

    @Test("Partial success (results + errors) still shows results — non-fatal errors don't block review")
    func partialSuccessBecomesResults() {
        let state = DuplicateFinderContainerState.deriveScanState(
            results: [Self.makeResult(id: "dup1")],
            errors: ["Couldn't read /some/subdir: permission denied"]
        )

        guard case .results(let results) = state else {
            Issue.record("Expected .results, got \(state)")
            return
        }
        #expect(results.count == 1)
        #expect(results.first?.id == "dup1")
    }

    @Test("Multiple errors are joined so the user sees every failure cause")
    func multipleErrorsJoined() {
        let state = DuplicateFinderContainerState.deriveScanState(
            results: [],
            errors: ["timed out", "parse failed"]
        )

        guard case .error(let message) = state else {
            Issue.record("Expected .error, got \(state)")
            return
        }
        #expect(message.contains("timed out"))
        #expect(message.contains("parse failed"))
    }

    // MARK: - Lifecycle transitions

    @Test("prepareForScan bumps the generation, drops the cache, and enters scanning")
    @MainActor
    func prepareForScanResets() {
        let state = DuplicateFinderContainerState()
        state.cachedResults = [Self.makeResult(id: "old")]
        state.cachedAt = Date()
        let generationBefore = state.scanGeneration

        state.prepareForScan()

        #expect(state.scanGeneration == generationBefore + 1)
        #expect(state.cachedResults == nil)
        #expect(state.cachedAt == nil)
        guard case .scanning = state.scanState else {
            Issue.record("Expected .scanning, got \(state.scanState)")
            return
        }
    }

    @Test("finishScan caches results on success")
    @MainActor
    func finishScanCachesResults() {
        let state = DuplicateFinderContainerState()
        state.prepareForScan()
        state.finishScan(results: [Self.makeResult(id: "a"), Self.makeResult(id: "b")], errors: [])

        guard case .results(let stored) = state.scanState else {
            Issue.record("Expected .results, got \(state.scanState)")
            return
        }
        #expect(stored.count == 2)
        #expect(state.cachedResults?.count == 2)
        #expect(state.cachedAt != nil)
    }

    @Test("finishScan with a silent failure does not populate the cache")
    @MainActor
    func finishScanFailureSkipsCache() {
        let state = DuplicateFinderContainerState()
        state.prepareForScan()
        state.finishScan(results: [], errors: ["fclones timed out"])

        guard case .error = state.scanState else {
            Issue.record("Expected .error, got \(state.scanState)")
            return
        }
        #expect(state.cachedResults == nil)
    }

    @Test("applyRefresh replaces both the live state and the cache")
    @MainActor
    func applyRefreshReplaces() {
        let state = DuplicateFinderContainerState()
        state.finishScan(results: [Self.makeResult(id: "a")], errors: [])

        state.applyRefresh(pruned: [Self.makeResult(id: "b"), Self.makeResult(id: "c")])

        guard case .results(let stored) = state.scanState else {
            Issue.record("Expected .results, got \(state.scanState)")
            return
        }
        #expect(stored.map(\.id) == ["b", "c"])
        #expect(state.cachedResults?.map(\.id) == ["b", "c"])
    }

    @Test("showCachedResults restores from cache, and is a no-op when empty")
    @MainActor
    func showCachedResultsRestores() {
        let state = DuplicateFinderContainerState()

        state.showCachedResults()
        guard case .idle = state.scanState else {
            Issue.record("Expected .idle with no cache, got \(state.scanState)")
            return
        }

        state.finishScan(results: [Self.makeResult(id: "a")], errors: [])
        state.returnToIdle()
        state.showCachedResults()

        guard case .results(let stored) = state.scanState else {
            Issue.record("Expected .results, got \(state.scanState)")
            return
        }
        #expect(stored.count == 1)
    }

    @Test("failScan moves to the error state")
    @MainActor
    func failScanSetsError() {
        let state = DuplicateFinderContainerState()
        state.failScan("disk unavailable")

        guard case .error(let message) = state.scanState else {
            Issue.record("Expected .error, got \(state.scanState)")
            return
        }
        #expect(message == "disk unavailable")
    }
}
