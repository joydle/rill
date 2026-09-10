import XCTest
import SwiftUI
@testable import RillUI
import RillCore
import RillAnalytics

/// Tests for the streaming entry points: ``MarkdownSource``,
/// ``StreamingMarkdownView``, and the static ``MarkdownView``.
///
/// These run headlessly. They assert on the `Document` a source publishes (never
/// pixels), prove streaming-equivalence against a one-shot parse, and use a
/// render-counting analytics sink to prove that appending text re-renders only
/// the live tail while every committed block is skipped.
@MainActor
final class StreamingViewTests: XCTestCase {

    private static let sample = """
    # Title

    First paragraph that is closed.

    Second paragraph still streaming
    """

    // MARK: - Streaming-equivalence of the source

    /// Appending text to a ``MarkdownSource`` must update its ``document``
    /// identically to parsing the whole string in one shot.
    func testAppendingTextMatchesOneShotParse() {
        let source = MarkdownSource()

        // Feed the sample in several word-boundary chunks.
        let chunks = Self.sample.split(separator: " ", omittingEmptySubsequences: false)
        for (i, chunk) in chunks.enumerated() {
            source.append(i == 0 ? String(chunk) : " " + chunk)
        }

        let oneShot = IncrementalParser()
        oneShot.consume(snapshot: Self.sample)

        XCTAssertEqual(source.document, oneShot.document,
                       "Chunked append must equal a one-shot parse of the same text.")
    }

    /// `setSnapshot` replaces the buffer wholesale and matches a one-shot parse.
    func testSetSnapshotMatchesOneShotParse() {
        let source = MarkdownSource()
        source.append("# Old\n\nstale")
        source.setSnapshot(Self.sample)

        let oneShot = IncrementalParser()
        oneShot.consume(snapshot: Self.sample)

        XCTAssertEqual(source.document, oneShot.document)
    }

    // MARK: - Static MarkdownView equals a fully-fed source

    /// The static ``MarkdownView`` must parse to the same ``Document`` as a
    /// ``MarkdownSource`` fed the whole string at once.
    func testStaticMarkdownViewMatchesSource() {
        let parsed = MarkdownView.parse(Self.sample)

        let source = MarkdownSource()
        source.setSnapshot(Self.sample)

        XCTAssertEqual(parsed, source.document)
    }

    /// `MarkdownView` exposes the public initializer shape (markdown, theme,
    /// config) and renders a `DocumentView` body without trapping.
    func testMarkdownViewBuildsBody() {
        let view = MarkdownView("# Hello\n\nworld", theme: .default, config: .default)
        _ = view.body
    }

    // MARK: - Tail-only re-render across appends (render-counting sink)

    /// Across a sequence of appends, the render-counting sink must show every
    /// previously-committed block skipped and only the freshly arriving tail
    /// rendered.
    func testStreamingReRendersOnlyTail() {
        let probe = RenderCountingSink()
        let source = MarkdownSource(analytics: probe)

        // Build a document where earlier blocks close as we stream.
        source.append("# Heading\n\n")          // heading still open as tail
        source.append("First paragraph.\n\n")   // heading commits; paragraph appears
        source.append("Second paragraph.\n\n")  // first paragraph commits
        source.append("Third paragraph.")       // second paragraph commits

        // Every report after the first must skip at least one committed block:
        // the heading (and earlier paragraphs) never re-render.
        XCTAssertFalse(probe.reports.isEmpty)

        // The total skipped count proves committed blocks are reused, not redrawn.
        XCTAssertGreaterThan(probe.totalSkipped, 0,
                             "Committed blocks must be skipped across appends.")

        // The final report renders only the live tail block, skipping the rest.
        let last = probe.reports.last!
        XCTAssertEqual(last.blocksRendered, 1,
                       "Only the live tail block should render on the final append.")
        XCTAssertEqual(last.blocksSkipped, source.document.blocks.count - 1,
                       "All committed blocks should be skipped on the final append.")
    }

    /// The render reporter is order-stable: rendered + skipped accounts for every
    /// block in the current document on each report.
    func testRenderReportAccountsForEveryBlock() {
        let probe = RenderCountingSink()
        let source = MarkdownSource(analytics: probe)
        source.append("# A\n\nB\n\nC")
        let report = probe.reports.last!
        XCTAssertEqual(report.blocksRendered + report.blocksSkipped,
                       source.document.blocks.count)
    }

    // MARK: - StreamingMarkdownView is not a second telemetry owner

    /// Regression: `StreamingMarkdownView.body` previously emitted its own
    /// (wrong) `RenderMetrics` on every evaluation, producing a second,
    /// conflicting `didRender` per update (all-rendered/none-skipped). The
    /// ``MarkdownSource`` is the single telemetry owner: each append emits exactly
    /// one report with correct skip accounting, and evaluating the view's body
    /// emits nothing extra.
    func testStreamingViewDoesNotDoubleEmitRenderMetrics() {
        let probe = RenderCountingSink()
        let source = MarkdownSource(analytics: probe)
        let view = StreamingMarkdownView(source, analytics: probe)

        source.append("# Heading\n\n")
        source.append("First paragraph.\n\n")
        source.append("Second paragraph.")

        // One report per append, no more.
        XCTAssertEqual(probe.reports.count, 3,
                       "Each update must emit exactly one RenderMetrics (from the source).")

        // Evaluating the view's body must not emit additional render metrics.
        _ = view.body
        XCTAssertEqual(probe.reports.count, 3,
                       "StreamingMarkdownView.body must not emit RenderMetrics.")

        // Every report is well-formed: non-negative block accounting.
        for report in probe.reports {
            XCTAssertGreaterThanOrEqual(report.blocksRendered, 0)
            XCTAssertGreaterThanOrEqual(report.blocksSkipped, 0)
        }
        let last = probe.reports.last!
        XCTAssertEqual(last.blocksRendered + last.blocksSkipped,
                       source.document.blocks.count)
        // Committed blocks were skipped, not redrawn as the old view claimed.
        XCTAssertGreaterThan(probe.totalSkipped, 0)
    }
}

// MARK: - Test doubles

/// Captures every ``RenderMetrics`` reported through the analytics sink so a test
/// can prove only the tail re-renders across streamed appends.
private final class RenderCountingSink: MarkdownAnalytics, @unchecked Sendable {
    private(set) var reports: [RenderMetrics] = []
    var totalSkipped: Int { reports.reduce(0) { $0 + $1.blocksSkipped } }
    var totalRendered: Int { reports.reduce(0) { $0 + $1.blocksRendered } }

    func didParse(_ metrics: ParseMetrics) {}
    func didRender(_ metrics: RenderMetrics) { reports.append(metrics) }
    func didInteract(_ interaction: MarkdownInteraction) {}
}
