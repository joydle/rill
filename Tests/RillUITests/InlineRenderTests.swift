import XCTest
import SwiftUI
@testable import RillUI
import RillCore
import RillAnalytics

/// Tests for the RillUI inline renderers: ``InlineRenderer``, ``CitationPill``,
/// and the inline view fallbacks for images and inline math.
///
/// These run headlessly. They assert on the runs of the produced
/// `AttributedString` (presentation intents, fonts, links, strikethrough), on
/// the view-model state of ``CitationPill``, and on the `MarkdownInteraction`s a
/// probing analytics sink receives when an inline element is activated. There
/// are no pixel snapshots.
@MainActor
final class InlineRenderTests: XCTestCase {

    // MARK: - AttributedString structure

    /// Nested emphasis inside strong (`**bold *and italic* **`) must yield a run
    /// that carries *both* the italic (emphasized) and bold (strongly
    /// emphasized) presentation intents.
    func testNestedEmphasisYieldsItalicPlusBoldRuns() {
        // strong( [ text("bold "), emphasis( [ text("italic") ] ) ] )
        let inlines: [Inline] = [
            .strong([
                .text("bold "),
                .emphasis([.text("italic")]),
            ]),
        ]
        let attributed = InlineRenderer.attributed(inlines, theme: .default, config: .default)

        XCTAssertEqual(String(attributed.characters), "bold italic")

        // Find the run covering the nested "italic" text.
        let italicRun = run(in: attributed, containing: "italic")
        let intent = italicRun?.inlinePresentationIntent ?? []
        XCTAssertTrue(intent.contains(.emphasized),
                      "Nested emphasis must contribute an italic (emphasized) intent.")
        XCTAssertTrue(intent.contains(.stronglyEmphasized),
                      "The surrounding strong must contribute a bold (strongly emphasized) intent.")

        // The non-nested "bold " portion carries only the strong intent.
        let boldRun = run(in: attributed, containing: "bold")
        let boldIntent = boldRun?.inlinePresentationIntent ?? []
        XCTAssertTrue(boldIntent.contains(.stronglyEmphasized))
        XCTAssertFalse(boldIntent.contains(.emphasized))
    }

    /// An inline code span must render in the theme's code font.
    func testCodeRunUsesCodeFont() {
        let attributed = InlineRenderer.attributed(
            [.text("call "), .code("foo()")],
            theme: .default,
            config: .default
        )
        let codeRun = run(in: attributed, containing: "foo()")
        XCTAssertEqual(codeRun?.font, RillTheme.default.fonts.code,
                       "An inline code span must use the theme's code font.")
        // Plain text adjacent to it must NOT inherit the code font.
        let textRun = run(in: attributed, containing: "call")
        XCTAssertNotEqual(textRun?.font, RillTheme.default.fonts.code)
    }

    /// A link run must carry its destination URL as the `.link` attribute.
    func testLinkRunCarriesURL() {
        let link = Link(inlines: [.text("Rill")], url: "https://example.com/rill", title: nil)
        let attributed = InlineRenderer.attributed([.link(link)], theme: .default, config: .default)

        let linkRun = run(in: attributed, containing: "Rill")
        XCTAssertEqual(linkRun?.link, URL(string: "https://example.com/rill"),
                       "A link run must carry its url attribute.")
    }

    /// A strikethrough run must set the strikethrough style attribute.
    func testStrikethroughRunIsSet() {
        let attributed = InlineRenderer.attributed(
            [.text("keep "), .strikethrough([.text("gone")])],
            theme: .default,
            config: .default
        )
        let struck = run(in: attributed, containing: "gone")
        XCTAssertEqual(struck?.strikethroughStyle, .single,
                       "A strikethrough inline must set the single strikethrough style.")
        XCTAssertNil(run(in: attributed, containing: "keep")?.strikethroughStyle,
                     "Adjacent plain text must not be struck through.")
    }

    /// Soft and hard breaks lower to a space and a newline respectively.
    func testBreaksLowerToWhitespace() {
        let attributed = InlineRenderer.attributed(
            [.text("a"), .softBreak, .text("b"), .lineBreak, .text("c")],
            theme: .default,
            config: .default
        )
        XCTAssertEqual(String(attributed.characters), "a b\nc")
    }

    // MARK: - Inline classification (images / math need views, not AttributedString)

    /// Plain inline content reduces to a single attributed segment; images and
    /// inline math become dedicated view segments because an `AttributedString`
    /// cannot express them.
    func testSegmentationSplitsOutImageAndMath() {
        let inlines: [Inline] = [
            .text("see "),
            .image(Image(alt: "logo", url: "https://example.com/logo.png", title: nil)),
            .text(" and "),
            .mathInline("x^2"),
            .text(" done"),
        ]
        let segments = InlineRenderer.segments(inlines, theme: .default, config: .default)

        // text → attributed; image → image segment; text → attributed; math →
        // math segment; text → attributed  ⇒ 5 segments.
        XCTAssertEqual(segments.count, 5)

        guard case .text = segments[0] else { return XCTFail("segment 0 should be text") }
        guard case .image(let image) = segments[1] else { return XCTFail("segment 1 should be image") }
        XCTAssertEqual(image.url, "https://example.com/logo.png")
        guard case .text = segments[2] else { return XCTFail("segment 2 should be text") }
        guard case .math(let latex) = segments[3] else { return XCTFail("segment 3 should be math") }
        XCTAssertEqual(latex, "x^2")
        guard case .text = segments[4] else { return XCTFail("segment 4 should be text") }
    }

    /// Numbered citations (`[1]`) stay inline as flowing attributed text so the
    /// paragraph renders as one naturally-wrapping, evenly-spaced `Text`. Only a
    /// footnote-style reference (no number, resolved against the registry) breaks
    /// out into its own segment so a view can render it as a superscript marker.
    func testNumberedCitationStaysInlineButFootnoteRefBreaksOut() {
        // Numbered citation: coalesces into a single flowing text segment.
        let numbered: [Inline] = [
            .text("see "),
            .citation(Citation(marker: "1", index: 1)),
            .text(" too"),
        ]
        let numberedSegments = InlineRenderer.segments(numbered, theme: .default, config: .default)
        XCTAssertEqual(numberedSegments.count, 1)
        guard case .text(let text) = numberedSegments[0] else {
            return XCTFail("a numbered citation should stay inline as one text segment")
        }
        XCTAssertTrue(String(text.characters).contains("[1]"))

        // Footnote-style reference (no index): breaks out into its own segment.
        let footnote: [Inline] = [
            .text("see "),
            .citation(Citation(marker: "note", index: nil)),
            .text(" too"),
        ]
        let footnoteSegments = InlineRenderer.segments(footnote, theme: .default, config: .default)
        XCTAssertEqual(footnoteSegments.count, 3)
        guard case .text = footnoteSegments[0] else { return XCTFail("segment 0 should be text") }
        guard case .citation(let citation) = footnoteSegments[1] else {
            return XCTFail("segment 1 should be a footnote citation")
        }
        XCTAssertEqual(citation.marker, "note")
        XCTAssertNil(citation.index)
        guard case .text = footnoteSegments[2] else { return XCTFail("segment 2 should be text") }
    }

    /// `RichInlineText` builds over mixed inline content (text, link, citation,
    /// inline math, image) without trapping — proving the segmented/interactive
    /// inline path is actually consumed by a view.
    func testRichInlineTextBuildsOverMixedContent() {
        let context = BlockRenderContext(theme: .default, config: .default, analytics: NoopAnalytics())
        let view = RichInlineText(
            inlines: [
                .text("see "),
                .link(Link(inlines: [.text("here")], url: "https://example.com", title: nil)),
                .text(" "),
                .citation(Citation(marker: "1", index: 1)),
                .mathInline("x^2"),
                .image(Image(alt: "logo", url: "https://example.com/logo.png", title: nil)),
            ],
            context: context
        )
        _ = view.body
    }

    // MARK: - CitationPill

    /// A resolvable citation builds a pill whose label reflects the resolved
    /// title and whose tap fires both the resolver and `citationTapped`.
    func testCitationPillTapFiresResolverAndAnalytics() {
        let probe = InteractionProbe()
        let resolved = Recorder<String>()
        let config = RenderConfig(
            citationResolver: { marker in
                resolved.append(marker)
                return CitationTarget(title: "Source \(marker)", url: "https://example.com/\(marker)")
            }
        )
        let context = BlockRenderContext(theme: .default, config: config, analytics: probe)
        let pill = CitationPill(
            citation: Citation(marker: "1", index: 1),
            context: context
        )

        // The pill resolves its target for its label.
        XCTAssertEqual(pill.model.target?.title, "Source 1")
        XCTAssertEqual(String(pill.model.label.characters), "1")

        pill.performTap()

        XCTAssertEqual(resolved.values, ["1"],
                       "Tapping the pill must invoke the citation resolver.")
        XCTAssertEqual(probe.interactions, [.citationTapped(marker: "1", index: 1)],
                       "Tapping the pill must fire citationTapped with marker and index.")
    }

    /// A pill builds even when the marker does not resolve; its target is nil and
    /// a tap still reports the interaction.
    func testCitationPillUnresolvedStillReportsTap() {
        let probe = InteractionProbe()
        let context = BlockRenderContext(theme: .default, config: .default, analytics: probe)
        let pill = CitationPill(
            citation: Citation(marker: "ref", index: nil),
            context: context
        )
        XCTAssertNil(pill.model.target)
        pill.performTap()
        XCTAssertEqual(probe.interactions, [.citationTapped(marker: "ref", index: nil)])
    }

    // MARK: - Link tap

    /// Activating a link segment fires `linkTapped` with the destination as
    /// written and, when present, invokes the host link handler.
    func testLinkActivationFiresLinkTapped() {
        let probe = InteractionProbe()
        let handled = Recorder<URL>()
        let config = RenderConfig(linkHandler: { url in handled.append(url) })
        let context = BlockRenderContext(theme: .default, config: config, analytics: probe)

        InlineRenderer.handleLinkTap(
            url: "https://example.com/page",
            context: context
        )

        XCTAssertEqual(probe.interactions, [.linkTapped(url: "https://example.com/page")])
        XCTAssertEqual(handled.values, [URL(string: "https://example.com/page")])
    }

    // MARK: - Helpers

    /// Returns the first run whose substring contains `needle`.
    private func run(
        in attributed: AttributedString,
        containing needle: String
    ) -> AttributedString.Runs.Run? {
        for run in attributed.runs {
            let segment = String(attributed[run.range].characters)
            if segment.contains(needle) {
                return run
            }
        }
        return nil
    }
}

// MARK: - Test doubles

/// Captures `MarkdownInteraction`s fired by inline tap handlers.
private final class InteractionProbe: MarkdownAnalytics, @unchecked Sendable {
    private(set) var interactions: [MarkdownInteraction] = []
    func didParse(_ metrics: ParseMetrics) {}
    func didRender(_ metrics: RenderMetrics) {}
    func didInteract(_ interaction: MarkdownInteraction) { interactions.append(interaction) }
}

/// A minimal `Sendable` recorder so `@Sendable` config closures can append to a
/// shared list without tripping Swift 6's captured-`var` mutation check.
private final class Recorder<Element>: @unchecked Sendable {
    private(set) var values: [Element] = []
    func append(_ value: Element) { values.append(value) }
}
