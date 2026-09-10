import XCTest
@testable import RillAnalytics

/// Behavioural tests for the RillAnalytics protocol, metrics value types, and
/// sinks. These tests are headless: they assert on recorded calls rather than
/// on any rendered output.
final class AnalyticsTests: XCTestCase {

    // MARK: - Test fixtures

    /// Builds a representative `ParseMetrics` value.
    private func sampleParseMetrics(
        dirtyTailBytes: Int = 42,
        blocksReused: Int = 3
    ) -> ParseMetrics {
        ParseMetrics(
            duration: .milliseconds(2),
            dirtyTailBytes: dirtyTailBytes,
            totalBytes: 1_024,
            blocksCommitted: 7,
            blocksReused: blocksReused
        )
    }

    /// Builds a representative `RenderMetrics` value.
    private func sampleRenderMetrics(blocksSkipped: Int = 5) -> RenderMetrics {
        RenderMetrics(
            blocksRendered: 2,
            blocksSkipped: blocksSkipped
        )
    }

    /// A render-counting analytics sink that records every call it receives so
    /// tests can assert on counts and payloads without touching any UI.
    private final class RecordingSink: MarkdownAnalytics, @unchecked Sendable {
        private(set) var parseCalls: [ParseMetrics] = []
        private(set) var renderCalls: [RenderMetrics] = []
        private(set) var interactions: [MarkdownInteraction] = []

        func didParse(_ metrics: ParseMetrics) { parseCalls.append(metrics) }
        func didRender(_ metrics: RenderMetrics) { renderCalls.append(metrics) }
        func didInteract(_ interaction: MarkdownInteraction) { interactions.append(interaction) }
    }

    // MARK: - Metrics value types

    func testParseMetricsStoresAllFields() {
        let metrics = sampleParseMetrics()
        XCTAssertEqual(metrics.duration, .milliseconds(2))
        XCTAssertEqual(metrics.dirtyTailBytes, 42)
        XCTAssertEqual(metrics.totalBytes, 1_024)
        XCTAssertEqual(metrics.blocksCommitted, 7)
        XCTAssertEqual(metrics.blocksReused, 3)
    }

    func testRenderMetricsStoresAllFields() {
        let metrics = sampleRenderMetrics()
        XCTAssertEqual(metrics.blocksRendered, 2)
        XCTAssertEqual(metrics.blocksSkipped, 5)
    }

    func testMarkdownInteractionCasesCarryPayloads() {
        let interactions: [MarkdownInteraction] = [
            .linkTapped(url: "https://example.com"),
            .codeCopied(language: "swift"),
            .codeCopied(language: nil),
            .citationTapped(marker: "1", index: 0),
            .citationTapped(marker: "ref", index: nil),
            .tableCopied(rows: 3, columns: 4),
            .imageTapped(url: "https://example.com/cat.png"),
        ]

        if case let .linkTapped(url) = interactions[0] {
            XCTAssertEqual(url, "https://example.com")
        } else {
            XCTFail("expected linkTapped")
        }
        if case let .codeCopied(language) = interactions[1] {
            XCTAssertEqual(language, "swift")
        } else {
            XCTFail("expected codeCopied")
        }
        if case let .codeCopied(language) = interactions[2] {
            XCTAssertNil(language)
        } else {
            XCTFail("expected codeCopied")
        }
        if case let .citationTapped(marker, index) = interactions[3] {
            XCTAssertEqual(marker, "1")
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("expected citationTapped")
        }
        if case let .tableCopied(rows, columns) = interactions[5] {
            XCTAssertEqual(rows, 3)
            XCTAssertEqual(columns, 4)
        } else {
            XCTFail("expected tableCopied")
        }
        if case let .imageTapped(url) = interactions[6] {
            XCTAssertEqual(url, "https://example.com/cat.png")
        } else {
            XCTFail("expected imageTapped")
        }
    }

    func testMarkdownInteractionIsEquatable() {
        XCTAssertEqual(
            MarkdownInteraction.citationTapped(marker: "1", index: 2),
            MarkdownInteraction.citationTapped(marker: "1", index: 2)
        )
        XCTAssertNotEqual(
            MarkdownInteraction.codeCopied(language: "swift"),
            MarkdownInteraction.codeCopied(language: nil)
        )
    }

    // MARK: - NoopAnalytics

    func testNoopAnalyticsNeverCrashes() {
        let noop = NoopAnalytics()
        noop.didParse(sampleParseMetrics())
        noop.didRender(sampleRenderMetrics())
        noop.didInteract(.linkTapped(url: "https://example.com"))
        noop.didInteract(.codeCopied(language: nil))
        noop.didInteract(.tableCopied(rows: 0, columns: 0))
        // Reaching here without trapping is the assertion.
    }

    // MARK: - Recording sink

    func testRecordingSinkRecordsRenderCalls() {
        let sink = RecordingSink()
        XCTAssertEqual(sink.renderCalls.count, 0)

        sink.didRender(sampleRenderMetrics(blocksSkipped: 1))
        sink.didRender(sampleRenderMetrics(blocksSkipped: 2))

        XCTAssertEqual(sink.renderCalls.count, 2)
        XCTAssertEqual(sink.renderCalls[0].blocksSkipped, 1)
        XCTAssertEqual(sink.renderCalls[1].blocksSkipped, 2)
    }

    // MARK: - MultiplexAnalytics

    func testMultiplexFansOutParseToAllChildren() {
        let a = RecordingSink()
        let b = RecordingSink()
        let c = RecordingSink()
        let multiplex = MultiplexAnalytics([a, b, c])

        multiplex.didParse(sampleParseMetrics(dirtyTailBytes: 99))

        for child in [a, b, c] {
            XCTAssertEqual(child.parseCalls.count, 1)
            XCTAssertEqual(child.parseCalls.first?.dirtyTailBytes, 99)
        }
    }

    func testMultiplexFansOutRenderToAllChildren() {
        let a = RecordingSink()
        let b = RecordingSink()
        let multiplex = MultiplexAnalytics([a, b])

        multiplex.didRender(sampleRenderMetrics(blocksSkipped: 7))

        XCTAssertEqual(a.renderCalls.first?.blocksSkipped, 7)
        XCTAssertEqual(b.renderCalls.first?.blocksSkipped, 7)
    }

    func testMultiplexFansOutInteractionToAllChildren() {
        let a = RecordingSink()
        let b = RecordingSink()
        let multiplex = MultiplexAnalytics([a, b])

        multiplex.didInteract(.tableCopied(rows: 2, columns: 5))

        XCTAssertEqual(a.interactions.first, .tableCopied(rows: 2, columns: 5))
        XCTAssertEqual(b.interactions.first, .tableCopied(rows: 2, columns: 5))
    }

    func testMultiplexWithNoChildrenNeverCrashes() {
        let multiplex = MultiplexAnalytics([])
        multiplex.didParse(sampleParseMetrics())
        multiplex.didRender(sampleRenderMetrics())
        multiplex.didInteract(.imageTapped(url: "https://example.com/x.png"))
        // Reaching here without trapping is the assertion.
    }

    func testMultiplexPreservesChildOrderAndAllCallKinds() {
        let sink = RecordingSink()
        let multiplex = MultiplexAnalytics([sink])

        multiplex.didParse(sampleParseMetrics())
        multiplex.didRender(sampleRenderMetrics())
        multiplex.didInteract(.linkTapped(url: "https://example.com"))

        XCTAssertEqual(sink.parseCalls.count, 1)
        XCTAssertEqual(sink.renderCalls.count, 1)
        XCTAssertEqual(sink.interactions.count, 1)
    }

    // MARK: - OSLogAnalytics

    func testOSLogAnalyticsNeverCrashes() {
        let sink = OSLogAnalytics()
        sink.didParse(sampleParseMetrics())
        sink.didRender(sampleRenderMetrics())
        sink.didInteract(.codeCopied(language: "swift"))
        sink.didInteract(.citationTapped(marker: "1", index: nil))
        // Reaching here without trapping is the assertion.
    }

    func testOSLogAnalyticsCustomSubsystemNeverCrashes() {
        let sink = OSLogAnalytics(subsystem: "com.example.app", category: "markdown")
        sink.didParse(sampleParseMetrics())
        sink.didRender(sampleRenderMetrics())
        sink.didInteract(.imageTapped(url: "https://example.com/x.png"))
        // Reaching here without trapping is the assertion.
    }

    // MARK: - Protocol conformance via existential

    func testProtocolUsableAsExistential() {
        let sinks: [any MarkdownAnalytics] = [
            NoopAnalytics(),
            OSLogAnalytics(),
            MultiplexAnalytics([NoopAnalytics()]),
        ]
        for sink in sinks {
            sink.didParse(sampleParseMetrics())
            sink.didRender(sampleRenderMetrics())
            sink.didInteract(.linkTapped(url: "https://example.com"))
        }
    }
}
