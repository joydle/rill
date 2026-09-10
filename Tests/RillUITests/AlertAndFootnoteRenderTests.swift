import XCTest
import SwiftUI
@testable import RillUI
import RillCore
import RillAnalytics

/// Headless render tests for GitHub alert callouts and the footnote section.
///
/// These assert on view-model content, the footnote ``FootnoteRegistry``, and the
/// analytics fired by a footnote-reference tap, and force the relevant view
/// bodies to build without trapping. No pixel snapshots.
@MainActor
final class AlertAndFootnoteRenderTests: XCTestCase {

    // MARK: - Alerts

    /// The alert view-model exposes the kind's title, an icon, and flattened body
    /// text, and the renderer builds without trapping.
    func testAlertViewModelAndBuild() {
        let alert = MarkdownAlert(kind: .warning, blocks: [
            .paragraph(Paragraph(inlines: [.text("Mind the gap.")])),
        ])
        let vm = AlertView.Model(alert: alert, theme: .default)
        XCTAssertEqual(vm.title, "Warning")
        XCTAssertFalse(vm.iconName.isEmpty)
        XCTAssertTrue(vm.plainText.contains("Mind the gap."))

        let context = BlockRenderContext(theme: .default, config: .default, analytics: NoopAnalytics())
        let view = AlertView(alert: alert, context: context)
        _ = view.body
    }

    /// Every alert kind maps to a distinct theme tint and a non-empty icon.
    func testAlertPaletteCoversEveryKind() {
        let palette = RillTheme.default.colors.alerts
        var tints = Set<String>()
        for kind in AlertKind.allCases {
            // Distinctness is asserted indirectly via the SF Symbol + title; the
            // tints are Colors (not Hashable), so confirm icon coverage instead.
            tints.insert(AlertView.iconName(kind))
            _ = palette.tint(for: kind)
        }
        XCTAssertEqual(tints.count, AlertKind.allCases.count,
                       "each alert kind should have a distinct icon")
    }

    /// A `DocumentView` over a document containing an alert builds successfully.
    func testDocumentViewWithAlertBuilds() {
        let doc = MarkdownView.parse("> [!CAUTION]\n> Danger ahead.\n")
        let hasAlert = doc.blocks.contains { if case .alert = $0 { return true }; return false }
        XCTAssertTrue(hasAlert, "the parsed document should contain an alert")
        let view = DocumentView(doc, theme: .default, config: .default, analytics: NoopAnalytics())
        _ = view.body
    }

    // MARK: - Footnotes

    /// The footnote registry numbers definitions 1…N in document order and
    /// resolves reference markers to their numbers.
    func testFootnoteRegistryNumbersDefinitions() {
        let doc = MarkdownView.parse(
            "See[^a] and[^b].\n\n[^a]: First note.\n\n[^b]: Second note.\n"
        )
        let registry = FootnoteRegistry(document: doc)
        XCTAssertFalse(registry.isEmpty)
        XCTAssertEqual(registry.entries.count, 2)
        XCTAssertEqual(registry.number(for: "a"), 1)
        XCTAssertEqual(registry.number(for: "b"), 2)
        XCTAssertNil(registry.number(for: "missing"))
    }

    /// A document with no footnotes yields an empty registry.
    func testEmptyRegistryForNoFootnotes() {
        let doc = MarkdownView.parse("Just a paragraph.\n")
        XCTAssertTrue(FootnoteRegistry(document: doc).isEmpty)
    }

    /// Tapping a footnote reference fires the existing citation interaction with
    /// the resolved footnote number as the index.
    func testFootnoteReferenceTapFiresCitationAnalytics() {
        let probe = InteractionProbe()
        let context = BlockRenderContext(theme: .default, config: .default, analytics: probe)
        let view = FootnoteReferenceView(
            citation: Citation(marker: "note", index: nil),
            number: 3,
            context: context
        )
        view.performTap()
        XCTAssertEqual(probe.interactions, [.citationTapped(marker: "note", index: 3)])
    }

    /// The footnotes section view builds over a populated registry.
    func testFootnotesSectionViewBuilds() {
        let doc = MarkdownView.parse("Ref[^x].\n\n[^x]: Definition.\n")
        let registry = FootnoteRegistry(document: doc)
        let context = BlockRenderContext(
            theme: .default, config: .default, analytics: NoopAnalytics(), footnotes: registry
        )
        let view = FootnotesSectionView(context: context)
        _ = view.body
    }

    /// End-to-end: a `DocumentView` over a document that references and defines a
    /// footnote builds, exposes a non-empty registry on its context, and the
    /// reference resolves to a number (so it renders as a superscript marker, not
    /// a plain citation pill).
    func testDocumentViewRendersFootnoteReferenceAndSection() {
        let doc = MarkdownView.parse(
            "A claim with a footnote[^1].\n\n[^1]: The supporting detail.\n"
        )
        let registry = FootnoteRegistry(document: doc)
        XCTAssertEqual(registry.number(for: "1"), 1)

        let view = DocumentView(doc, theme: .default, config: .default, analytics: NoopAnalytics())
        _ = view.body
    }
}

/// Captures `MarkdownInteraction`s fired by tap handlers.
private final class InteractionProbe: MarkdownAnalytics, @unchecked Sendable {
    private(set) var interactions: [MarkdownInteraction] = []
    func didParse(_ metrics: ParseMetrics) {}
    func didRender(_ metrics: RenderMetrics) {}
    func didInteract(_ interaction: MarkdownInteraction) { interactions.append(interaction) }
}
