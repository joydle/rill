import XCTest
@testable import RillCore

/// Tests for the RillCore AST model (spec §3): node construction, `Hashable`
/// conformance, and the stability of the stable-identity `id` (`NodeID`) across
/// equal values. The model is the foundation other Rill modules link against,
/// so these tests pin down the exact public shape and identity semantics.
final class ModelTests: XCTestCase {

    // MARK: - Construction

    func testDocumentConstruction() {
        let doc = Document(blocks: [
            .heading(Heading(level: 1, inlines: [.text("Title")])),
            .paragraph(Paragraph(inlines: [.text("Hello "), .strong([.text("world")])])),
        ])
        XCTAssertEqual(doc.blocks.count, 2)
    }

    func testHeadingConstruction() {
        let h = Heading(level: 3, inlines: [.text("Section")])
        XCTAssertEqual(h.level, 3)
        XCTAssertEqual(h.inlines, [.text("Section")])
    }

    func testParagraphConstruction() {
        let p = Paragraph(inlines: [.text("a"), .softBreak, .text("b")])
        XCTAssertEqual(p.inlines.count, 3)
    }

    func testBlockQuoteHoldsNestedBlocks() {
        let bq = BlockQuote(blocks: [.paragraph(Paragraph(inlines: [.text("quoted")]))])
        XCTAssertEqual(bq.blocks.count, 1)
    }

    func testListAndListItemConstruction() {
        let item = ListItem(
            blocks: [.paragraph(Paragraph(inlines: [.text("task")]))],
            checkbox: true
        )
        let list = List(items: [item], isOrdered: true, start: 3, isTight: false)
        XCTAssertTrue(list.isOrdered)
        XCTAssertEqual(list.start, 3)
        XCTAssertFalse(list.isTight)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].checkbox, true)
    }

    func testListItemCheckboxIsOptional() {
        let item = ListItem(blocks: [], checkbox: nil)
        XCTAssertNil(item.checkbox)
    }

    func testCodeBlockConstruction() {
        let cb = CodeBlock(language: "swift", content: "let x = 1\n", isClosed: false)
        XCTAssertEqual(cb.language, "swift")
        XCTAssertEqual(cb.content, "let x = 1\n")
        XCTAssertFalse(cb.isClosed)
    }

    func testCodeBlockLanguageIsOptional() {
        let cb = CodeBlock(language: nil, content: "x", isClosed: true)
        XCTAssertNil(cb.language)
        XCTAssertTrue(cb.isClosed)
    }

    func testTableConstruction() {
        let header: [[Inline]] = [[.text("A")], [.text("B")]]
        let rows: [[[Inline]]] = [
            [[.text("1")], [.text("2")]],
            [[.text("3")], [.text("4")]],
        ]
        let table = Table(
            header: header,
            rows: rows,
            alignments: [.left, .right]
        )
        XCTAssertEqual(table.header.count, 2)
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.alignments, [.left, .right])
    }

    func testColumnAlignmentCases() {
        let all: [ColumnAlignment] = [.none, .left, .center, .right]
        XCTAssertEqual(Set(all).count, 4)
    }

    func testMathBlockConstruction() {
        let m = MathBlock(latex: "a^2 + b^2 = c^2", isClosed: false)
        XCTAssertEqual(m.latex, "a^2 + b^2 = c^2")
        XCTAssertFalse(m.isClosed)
    }

    func testHTMLBlockConstruction() {
        let h = HTMLBlock(raw: "<div>x</div>")
        XCTAssertEqual(h.raw, "<div>x</div>")
    }

    func testLinkConstruction() {
        let link = Link(inlines: [.text("site")], url: "https://example.com", title: "T")
        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertEqual(link.title, "T")
        XCTAssertEqual(link.inlines, [.text("site")])
    }

    func testImageConstruction() {
        let img = Image(alt: "cat", url: "https://example.com/cat.png", title: nil)
        XCTAssertEqual(img.alt, "cat")
        XCTAssertEqual(img.url, "https://example.com/cat.png")
        XCTAssertNil(img.title)
    }

    func testCitationConstruction() {
        let c = Citation(marker: "1", index: 0)
        XCTAssertEqual(c.marker, "1")
        XCTAssertEqual(c.index, 0)
        let c2 = Citation(marker: "ref", index: nil)
        XCTAssertNil(c2.index)
    }

    func testInlineCasesConstruct() {
        let inlines: [Inline] = [
            .text("t"),
            .softBreak,
            .lineBreak,
            .emphasis([.text("i")]),
            .strong([.text("b")]),
            .strikethrough([.text("s")]),
            .code("x"),
            .link(Link(inlines: [.text("l")], url: "u", title: nil)),
            .image(Image(alt: "a", url: "u", title: nil)),
            .mathInline("x^2"),
            .citation(Citation(marker: "1", index: nil)),
            .rawHTML("<br>"),
        ]
        XCTAssertEqual(inlines.count, 12)
    }

    func testBlockCasesConstruct() {
        let blocks: [Block] = [
            .heading(Heading(level: 1, inlines: [])),
            .paragraph(Paragraph(inlines: [])),
            .blockQuote(BlockQuote(blocks: [])),
            .list(List(items: [], isOrdered: false, start: 1, isTight: true)),
            .codeBlock(CodeBlock(language: nil, content: "", isClosed: true)),
            .table(Table(header: [], rows: [], alignments: [])),
            .thematicBreak,
            .mathBlock(MathBlock(latex: "", isClosed: true)),
            .htmlBlock(HTMLBlock(raw: "")),
        ]
        XCTAssertEqual(blocks.count, 9)
    }

    // MARK: - NodeID

    func testNodeIDConstruction() {
        let id = NodeID(hash: 0xDEAD_BEEF)
        XCTAssertEqual(id.hash, 0xDEAD_BEEF)
    }

    func testNodeIDIsHashableAndEquatable() {
        let a = NodeID(hash: 1)
        let b = NodeID(hash: 1)
        let c = NodeID(hash: 2)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(Set([a, b, c]).count, 2)
    }

    // MARK: - Hashable conformance of model types

    func testEqualBlocksAreEqualAndHashEqual() {
        let a: Block = .paragraph(Paragraph(inlines: [.text("hi"), .emphasis([.text("x")])]))
        let b: Block = .paragraph(Paragraph(inlines: [.text("hi"), .emphasis([.text("x")])]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testDifferentBlocksAreNotEqual() {
        let a: Block = .paragraph(Paragraph(inlines: [.text("hi")]))
        let b: Block = .paragraph(Paragraph(inlines: [.text("bye")]))
        XCTAssertNotEqual(a, b)
    }

    func testEqualInlinesAreEqualAndHashEqual() {
        let a: Inline = .strong([.text("x"), .emphasis([.text("y")])])
        let b: Inline = .strong([.text("x"), .emphasis([.text("y")])])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testDocumentIsHashable() {
        let a = Document(blocks: [.thematicBreak])
        let b = Document(blocks: [.thematicBreak])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    // MARK: - Identity (id) stability across equal values

    func testEqualBlocksProduceEqualIDs() {
        let a: Block = .heading(Heading(level: 2, inlines: [.text("Hi")]))
        let b: Block = .heading(Heading(level: 2, inlines: [.text("Hi")]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, b.id, "Equal blocks must produce equal stable ids.")
    }

    func testDifferentBlocksProduceDifferentIDs() {
        let a: Block = .heading(Heading(level: 2, inlines: [.text("Hi")]))
        let b: Block = .heading(Heading(level: 2, inlines: [.text("Bye")]))
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEqualInlinesProduceEqualIDs() {
        let a: Inline = .code("let x = 1")
        let b: Inline = .code("let x = 1")
        XCTAssertEqual(a.id, b.id, "Equal inlines must produce equal stable ids.")
    }

    func testDifferentInlinesProduceDifferentIDs() {
        let a: Inline = .code("let x = 1")
        let b: Inline = .code("let x = 2")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testBlockIDIsDeterministicAcrossRepeatedComputation() {
        let block: Block = .paragraph(Paragraph(inlines: [.text("stable")]))
        XCTAssertEqual(block.id, block.id)
        // Recomputing on an independently-constructed equal value is identical,
        // i.e. the id is content-derived and not process-random.
        let same: Block = .paragraph(Paragraph(inlines: [.text("stable")]))
        XCTAssertEqual(block.id, same.id)
    }

    func testBlockIDDistinguishesCaseShape() {
        // Same payload string but different case wrappers must not collide.
        let para: Block = .paragraph(Paragraph(inlines: [.text("x")]))
        let head: Block = .heading(Heading(level: 1, inlines: [.text("x")]))
        XCTAssertNotEqual(para.id, head.id)
    }

    func testInlineIDDistinguishesCaseShape() {
        let code: Inline = .code("x")
        let text: Inline = .text("x")
        XCTAssertNotEqual(code.id, text.id)
    }

    func testNestedEqualityDrivesIDEquality() {
        let a: Block = .blockQuote(BlockQuote(blocks: [
            .paragraph(Paragraph(inlines: [.text("deep"), .strong([.text("nest")])])),
        ]))
        let b: Block = .blockQuote(BlockQuote(blocks: [
            .paragraph(Paragraph(inlines: [.text("deep"), .strong([.text("nest")])])),
        ]))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, b.id)
    }

    // MARK: - Sendable (compile-time)

    func testModelTypesAreSendable() {
        // Compiles only if every model type satisfies `Sendable`.
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        _ = requireSendable(Document(blocks: []))
        _ = requireSendable(Block.thematicBreak)
        _ = requireSendable(Inline.text("x"))
        _ = requireSendable(Heading(level: 1, inlines: []))
        _ = requireSendable(Paragraph(inlines: []))
        _ = requireSendable(BlockQuote(blocks: []))
        _ = requireSendable(List(items: [], isOrdered: false, start: 1, isTight: true))
        _ = requireSendable(ListItem(blocks: [], checkbox: nil))
        _ = requireSendable(CodeBlock(language: nil, content: "", isClosed: true))
        _ = requireSendable(Table(header: [], rows: [], alignments: []))
        _ = requireSendable(ColumnAlignment.none)
        _ = requireSendable(MathBlock(latex: "", isClosed: true))
        _ = requireSendable(HTMLBlock(raw: ""))
        _ = requireSendable(Link(inlines: [], url: "", title: nil))
        _ = requireSendable(Image(alt: "", url: "", title: nil))
        _ = requireSendable(Citation(marker: "", index: nil))
        _ = requireSendable(NodeID(hash: 0))
    }
}
