import XCTest
import SwiftUI
@testable import RillUI
import RillCore
import RillAnalytics

/// Tests for the RillUI block renderers, ``DocumentView``, and the
/// stable-identity ``EquatableBlockView``.
///
/// These run headlessly: they assert on the `Equatable` gating that drives
/// SwiftUI's skip-render behaviour, on the `RenderMetrics` a render-counting
/// analytics sink receives, and on the view-model / `AttributedString` content
/// each block view produces. There are no pixel snapshots.
@MainActor
final class BlockRenderTests: XCTestCase {

    // MARK: - Stable identity: EquatableBlockView gating

    /// The headline proof: an `EquatableBlockView` for a committed block whose
    /// `NodeID` is unchanged compares *equal* to its prior self, so SwiftUI
    /// skips its body. A view whose block changed compares *unequal*, so SwiftUI
    /// re-renders it.
    func testEquatableBlockViewComparesByNodeIdentity() {
        let context = BlockRenderContext(
            theme: .default,
            config: .default,
            analytics: NoopAnalytics()
        )
        let para = Block.paragraph(Paragraph(inlines: [.text("hello")]))
        let same = Block.paragraph(Paragraph(inlines: [.text("hello")]))
        let changed = Block.paragraph(Paragraph(inlines: [.text("hello world")]))

        let a = EquatableBlockView(block: para, context: context)
        let b = EquatableBlockView(block: same, context: context)
        let c = EquatableBlockView(block: changed, context: context)

        // Unchanged committed block ⇒ equal ⇒ SwiftUI skips the body.
        XCTAssertEqual(a, b)
        // Mutated tail block ⇒ unequal ⇒ SwiftUI re-evaluates the body.
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Tail-only re-render proof via render-counting analytics

    /// When the document grows by appending a new tail block, every previously
    /// committed block keeps its `NodeID`, so the document's render plan skips
    /// them all and renders only the new tail. We prove this with a
    /// render-counting sink: `blocksSkipped` equals the prior block count and
    /// `blocksRendered` equals the number of newly-appearing blocks.
    func testAppendingTailBlockSkipsPreviouslyCommittedBlocks() {
        let probe = RenderProbe()

        let first = Document(blocks: [
            .heading(Heading(level: 1, inlines: [.text("Title")])),
            .paragraph(Paragraph(inlines: [.text("First paragraph.")])),
        ])
        let second = Document(blocks: [
            .heading(Heading(level: 1, inlines: [.text("Title")])),
            .paragraph(Paragraph(inlines: [.text("First paragraph.")])),
            .paragraph(Paragraph(inlines: [.text("A freshly streamed tail.")])),
        ])

        // First pass: nothing previously rendered ⇒ everything renders.
        let m1 = DocumentRenderPlan.metrics(previous: nil, current: first)
        probe.record(m1)
        XCTAssertEqual(m1.blocksRendered, 2)
        XCTAssertEqual(m1.blocksSkipped, 0)

        // Second pass: the two committed blocks are byte-identical ⇒ skipped;
        // only the appended tail block renders.
        let m2 = DocumentRenderPlan.metrics(previous: first, current: second)
        probe.record(m2)
        XCTAssertEqual(m2.blocksSkipped, 2,
                       "Both committed blocks must be skipped on tail append.")
        XCTAssertEqual(m2.blocksRendered, 1,
                       "Only the newly appended tail block must render.")

        XCTAssertEqual(probe.totalRendered, 3)
        XCTAssertEqual(probe.totalSkipped, 2)
    }

    /// Editing the live tail block (as happens while a token streams into it)
    /// re-renders only that tail block; earlier committed blocks still skip.
    func testMutatingTailReRendersOnlyTail() {
        let first = Document(blocks: [
            .paragraph(Paragraph(inlines: [.text("committed")])),
            .paragraph(Paragraph(inlines: [.text("tai")])),
        ])
        let grown = Document(blocks: [
            .paragraph(Paragraph(inlines: [.text("committed")])),
            .paragraph(Paragraph(inlines: [.text("tail")])),
        ])
        let m = DocumentRenderPlan.metrics(previous: first, current: grown)
        XCTAssertEqual(m.blocksSkipped, 1)
        XCTAssertEqual(m.blocksRendered, 1)
    }

    // MARK: - DocumentView constructs over the full block catalogue

    /// `DocumentView` must accept the public initializer shape (document, theme,
    /// config, analytics) and build without trapping over every block kind.
    func testDocumentViewBuildsOverEveryBlockKind() {
        let doc = Document(blocks: BlockRenderTests.everyBlockKind)
        let view = DocumentView(
            doc,
            theme: .default,
            config: .default,
            analytics: NoopAnalytics()
        )
        // Building the view tree must not trap. Pull a body to force evaluation.
        _ = view.body
    }

    // MARK: - Per-block text / view-model assertions

    func testHeadingViewModelExposesLevelAndText() {
        let vm = HeadingView.Model(
            heading: Heading(level: 3, inlines: [.text("Section "), .strong([.text("A")])]),
            theme: .default
        )
        XCTAssertEqual(vm.level, 3)
        XCTAssertEqual(String(vm.text.characters), "Section A")
    }

    func testParagraphViewModelRendersInlineText() {
        let vm = ParagraphView.Model(
            paragraph: Paragraph(inlines: [.text("a "), .emphasis([.text("b")]), .text(" c")]),
            theme: .default,
            config: .default
        )
        XCTAssertEqual(String(vm.text.characters), "a b c")
    }

    func testQuoteViewModelFlattensNestedText() {
        let quote = BlockQuote(blocks: [
            .paragraph(Paragraph(inlines: [.text("quoted line")])),
        ])
        let vm = QuoteView.Model(quote: quote, theme: .default, config: .default)
        XCTAssertTrue(vm.plainText.contains("quoted line"))
    }

    func testListViewModelRowsCarryDepthOrdinalAndCheckbox() {
        let list = List(
            items: [
                ListItem(blocks: [.paragraph(Paragraph(inlines: [.text("one")]))], checkbox: nil),
                ListItem(blocks: [
                    .paragraph(Paragraph(inlines: [.text("two")])),
                    .list(List(
                        items: [
                            ListItem(blocks: [.paragraph(Paragraph(inlines: [.text("nested")]))],
                                     checkbox: true),
                        ],
                        isOrdered: false, start: 1, isTight: true
                    )),
                ], checkbox: nil),
            ],
            isOrdered: true, start: 1, isTight: true
        )
        let vm = ListView.Model(list: list, theme: .default, config: .default)

        // Top-level ordered markers start at the list's `start`.
        XCTAssertEqual(vm.rows[0].marker, "1.")
        XCTAssertEqual(vm.rows[0].depth, 0)
        XCTAssertEqual(String(vm.rows[0].text.characters), "one")

        XCTAssertEqual(vm.rows[1].marker, "2.")

        // The nested list contributes a deeper row with a checkbox.
        let nested = vm.rows.first { $0.depth == 1 }
        XCTAssertNotNil(nested)
        XCTAssertEqual(nested?.checkbox, true)
        XCTAssertEqual(String(nested!.text.characters), "nested")
    }

    func testCodeBlockViewModelPreservesContentAndCopyPayload() {
        let block = CodeBlock(language: "swift", content: "let x = 1\nprint(x)", isClosed: true)
        let vm = CodeBlockView.Model(codeBlock: block, theme: .default)
        XCTAssertEqual(vm.language, "swift")
        XCTAssertEqual(vm.copyText, "let x = 1\nprint(x)")
        XCTAssertEqual(vm.lineCount, 2)
    }

    /// The code block's copy button must fire `didInteract(.codeCopied)`.
    func testCodeBlockCopyFiresAnalytics() {
        let probe = InteractionProbe()
        let context = BlockRenderContext(theme: .default, config: .default, analytics: probe)
        let view = CodeBlockView(
            codeBlock: CodeBlock(language: "python", content: "print('hi')", isClosed: true),
            context: context
        )
        view.performCopy()
        XCTAssertEqual(probe.interactions, [.codeCopied(language: "python")])
    }

    /// The code block honors ``CodeBlockStyle``: the tappable-card presentation
    /// builds, and the model exposes the line count the style caps its preview
    /// against (`maxPreviewLines`).
    func testCodeBlockViewHonorsTappableCardStyle() {
        var theme = RillTheme.default
        theme.codeBlock = .tappableCard(maxPreviewLines: 3)
        let context = BlockRenderContext(theme: theme, config: .default, analytics: NoopAnalytics())
        let longCode = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let view = CodeBlockView(
            codeBlock: CodeBlock(language: "swift", content: longCode, isClosed: true),
            context: context
        )
        // Building the tappable-card body must not trap.
        _ = view.body

        let model = CodeBlockView.Model(
            codeBlock: CodeBlock(language: nil, content: longCode, isClosed: true),
            theme: theme
        )
        XCTAssertEqual(model.lineCount, 20)
        XCTAssertGreaterThan(model.lineCount, theme.codeBlock.maxPreviewLines,
                             "A long listing exceeds the preview cap so the card truncates / scrolls.")
    }

    /// The inline-scrollable style (the default) also builds and reads its cap.
    func testCodeBlockViewInlineScrollableStyleBuilds() {
        let context = BlockRenderContext(theme: .default, config: .default, analytics: NoopAnalytics())
        let view = CodeBlockView(
            codeBlock: CodeBlock(language: nil, content: "a\nb\nc", isClosed: true),
            context: context
        )
        _ = view.body
        if case .inlineScrollable = RillTheme.default.codeBlock {
            // expected default
        } else {
            XCTFail("Default theme should use the inline-scrollable code style.")
        }
    }

    func testTableViewModelHonorsAlignmentAndCells() {
        let table = Table(
            header: [[.text("Name")], [.text("Score")]],
            rows: [
                [[.text("Ada")], [.text("99")]],
                [[.text("Bob")], [.text("42")]],
            ],
            alignments: [.left, .right]
        )
        let vm = TableView.Model(table: table, theme: .default, config: .default)
        XCTAssertEqual(vm.columnCount, 2)
        XCTAssertEqual(vm.rowCount, 2)
        XCTAssertEqual(vm.alignment(forColumn: 0), .leading)
        XCTAssertEqual(vm.alignment(forColumn: 1), .trailing)
        XCTAssertEqual(String(vm.headerText(column: 0).characters), "Name")
        XCTAssertEqual(String(vm.bodyText(row: 0, column: 1).characters), "99")
    }

    /// The table's copy action must fire `didInteract(.tableCopied)` with the
    /// correct dimensions.
    func testTableCopyFiresAnalytics() {
        let probe = InteractionProbe()
        let context = BlockRenderContext(theme: .default, config: .default, analytics: probe)
        let table = Table(
            header: [[.text("A")], [.text("B")]],
            rows: [[[.text("1")], [.text("2")]]],
            alignments: [.none, .none]
        )
        let view = TableView(table: table, context: context)
        view.performCopy()
        XCTAssertEqual(probe.interactions, [.tableCopied(rows: 1, columns: 2)])
    }

    func testHTMLBlockViewModelEscapesMarkup() {
        let vm = HTMLBlockView.Model(html: HTMLBlock(raw: "<b>hi & bye</b>"))
        // The raw markup is shown verbatim as escaped text, never interpreted.
        XCTAssertEqual(vm.escapedText, "<b>hi & bye</b>")
        XCTAssertTrue(vm.isRenderedAsPlainText)
    }

    func testThematicBreakViewBuilds() {
        let view = ThematicBreakView(theme: .default)
        _ = view.body
    }

    func testMathBlockViewModelCarriesLatexAndClosedState() {
        let vm = MathBlockView.Model(
            mathBlock: MathBlock(latex: "\\frac{a}{b}", isClosed: true),
            theme: .default
        )
        XCTAssertEqual(vm.latex, "\\frac{a}{b}")
        XCTAssertTrue(vm.isClosed)
        // Until the Task 12 math views render glyphs, the fallback text shows the
        // raw LaTeX so a streamed equation is never blank.
        XCTAssertEqual(vm.fallbackText, "\\frac{a}{b}")
    }

    // MARK: - Fixtures

    static let everyBlockKind: [Block] = [
        .heading(Heading(level: 1, inlines: [.text("H1")])),
        .heading(Heading(level: 6, inlines: [.text("H6")])),
        .paragraph(Paragraph(inlines: [.text("para "), .emphasis([.text("em")]), .code("c")])),
        .blockQuote(BlockQuote(blocks: [.paragraph(Paragraph(inlines: [.text("q")]))])),
        .alert(MarkdownAlert(kind: .note, blocks: [.paragraph(Paragraph(inlines: [.text("callout")]))])),
        .footnoteDefinition(FootnoteDefinition(marker: "1", blocks: [.paragraph(Paragraph(inlines: [.text("def")]))])),
        .list(List(
            items: [
                ListItem(blocks: [.paragraph(Paragraph(inlines: [.text("x")]))], checkbox: false),
                ListItem(blocks: [.paragraph(Paragraph(inlines: [.text("y")]))], checkbox: true),
            ],
            isOrdered: false, start: 1, isTight: true
        )),
        .codeBlock(CodeBlock(language: "swift", content: "let a = 1", isClosed: true)),
        .table(Table(
            header: [[.text("h1")], [.text("h2")]],
            rows: [[[.text("a")], [.text("b")]]],
            alignments: [.center, .right]
        )),
        .thematicBreak,
        .mathBlock(MathBlock(latex: "x^2", isClosed: true)),
        .htmlBlock(HTMLBlock(raw: "<div>raw</div>")),
    ]
}

// MARK: - Test doubles

/// Accumulates `RenderMetrics` so a test can prove how many blocks were drawn
/// versus skipped across document updates.
private final class RenderProbe: @unchecked Sendable {
    private(set) var totalRendered = 0
    private(set) var totalSkipped = 0
    func record(_ m: RenderMetrics) {
        totalRendered += m.blocksRendered
        totalSkipped += m.blocksSkipped
    }
}

/// Captures `MarkdownInteraction`s fired by copy buttons / tap handlers.
private final class InteractionProbe: MarkdownAnalytics, @unchecked Sendable {
    private(set) var interactions: [MarkdownInteraction] = []
    func didParse(_ metrics: ParseMetrics) {}
    func didRender(_ metrics: RenderMetrics) {}
    func didInteract(_ interaction: MarkdownInteraction) { interactions.append(interaction) }
}
