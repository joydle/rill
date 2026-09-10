import XCTest
import RillAnalytics
@testable import RillCore

/// A capturing analytics sink that records every ``ParseMetrics`` emitted, so
/// tests can assert on dirty-tail size, commit/reuse counts, and per-delta timing.
final class CapturingAnalytics: MarkdownAnalytics, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var parseMetrics: [ParseMetrics] = []

    func didParse(_ metrics: ParseMetrics) {
        lock.lock(); defer { lock.unlock() }
        parseMetrics.append(metrics)
    }
    func didRender(_ metrics: RenderMetrics) {}
    func didInteract(_ interaction: MarkdownInteraction) {}
}

/// Performance contract: per-delta parse time stays roughly constant as the
/// document grows (O(dirty tail), not O(buffer)), and is strictly cheaper than
/// re-parsing the entire buffer on every delta.
final class ParsePerfTests: XCTestCase {

    /// Builds a long document as a list of one-line deltas, each a closed block
    /// so the dirty tail stays bounded.
    private func lineDeltas(_ count: Int) -> [String] {
        (0..<count).map { i in
            // Alternate paragraph + blank line so each paragraph commits.
            "Paragraph number \(i) with some words.\n\n"
        }
    }

    /// Per-delta parse time must not grow with document size: the average
    /// duration of the last quarter of deltas must be within a small multiple of
    /// the first quarter's average.
    func testPerDeltaTimeStaysConstant() {
        let analytics = CapturingAnalytics()
        let parser = IncrementalParser(analytics: analytics)
        let deltas = lineDeltas(200)
        var offset = 0
        for delta in deltas {
            parser.consume(delta: delta, at: offset)
            offset += delta.utf8.count
        }
        let metrics = analytics.parseMetrics
        XCTAssertEqual(metrics.count, deltas.count)

        // dirtyTailBytes must stay bounded (not grow toward totalBytes).
        let lastTotal = metrics.last!.totalBytes
        let maxDirty = metrics.map(\.dirtyTailBytes).max() ?? 0
        XCTAssertLessThan(maxDirty, lastTotal / 4,
                          "dirty tail must stay small relative to total buffer")

        // Timing: average of last quarter vs first quarter.
        let q = metrics.count / 4
        func avg(_ slice: ArraySlice<ParseMetrics>) -> Double {
            let secs = slice.map { Double($0.duration.components.attoseconds) / 1e18
                + Double($0.duration.components.seconds) }
            return secs.reduce(0, +) / Double(slice.count)
        }
        let firstAvg = avg(metrics[0..<q])
        let lastAvg = avg(metrics[(metrics.count - q)..<metrics.count])
        // Allow generous slack for scheduler noise; the point is no linear growth.
        if firstAvg > 0 {
            XCTAssertLessThan(lastAvg, firstAvg * 8.0 + 1e-4,
                              "per-delta time grew with document size (not O(tail))")
        }
    }

    /// The incremental parser must do strictly less total work than a naive
    /// engine that re-lexes and re-resolves the entire buffer on every delta.
    func testIncrementalBeatsFullReparse() {
        let deltas = lineDeltas(200)

        // Incremental: accumulate measured durations from analytics.
        let analytics = CapturingAnalytics()
        let parser = IncrementalParser(analytics: analytics)
        var offset = 0
        let incStart = ContinuousClock.now
        for delta in deltas {
            parser.consume(delta: delta, at: offset)
            offset += delta.utf8.count
        }
        let incElapsed = ContinuousClock.now - incStart

        // Full reparse baseline: rebuild the whole document each delta.
        var buffer = ""
        let fullStart = ContinuousClock.now
        for delta in deltas {
            buffer += delta
            let bytes = Array(buffer.utf8)
            let blocks = BlockLexer.lex(bytes[...])
            _ = InlineParser.resolveInlines(in: blocks, config: .default)
        }
        let fullElapsed = ContinuousClock.now - fullStart

        XCTAssertLessThan(incElapsed, fullElapsed,
                          "incremental parsing must beat full re-parse per delta")
    }

    /// Committed blocks must be reused via memoization across deltas: once the
    /// document has many committed blocks, later passes report `blocksReused > 0`.
    func testBlocksReusedAcrossDeltas() {
        let analytics = CapturingAnalytics()
        let parser = IncrementalParser(analytics: analytics)
        let deltas = lineDeltas(30)
        var offset = 0
        for delta in deltas {
            parser.consume(delta: delta, at: offset)
            offset += delta.utf8.count
        }
        let totalReused = analytics.parseMetrics.map(\.blocksReused).reduce(0, +)
        XCTAssertGreaterThan(totalReused, 0,
                             "committed blocks must be reused via memoization")
        // The last pass should have committed paragraphs reused, not re-resolved.
        XCTAssertGreaterThan(analytics.parseMetrics.last!.blocksReused, 0)
    }
}
