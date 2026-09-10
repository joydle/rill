import XCTest
@testable import RillCore

/// Golden tests for GitHub alerts and GFM footnotes: alert-kind recognition,
/// the no-misclassification guarantee for ordinary block quotes, footnote
/// definition parsing, and footnote reference/definition round-tripping.
final class AlertAndFootnoteGoldenTests: XCTestCase {

    // MARK: - GitHub alerts

    /// Every alert marker (`[!NOTE]` … `[!CAUTION]`) is recognized as an
    /// ``Alert`` of the matching ``AlertKind``, carrying its body as nested blocks.
    func testEachAlertKindRecognized() {
        let cases: [(String, AlertKind)] = [
            ("NOTE", .note),
            ("TIP", .tip),
            ("IMPORTANT", .important),
            ("WARNING", .warning),
            ("CAUTION", .caution),
        ]
        for (token, kind) in cases {
            let blocks = Golden.lex("> [!\(token)]\n> Body text.\n")
            XCTAssertEqual(blocks.count, 1, "\(token): expected one block")
            guard case .alert(let alert) = blocks[0] else {
                return XCTFail("\(token): expected an alert, got \(blocks[0])")
            }
            XCTAssertEqual(alert.kind, kind)
            XCTAssertEqual(Golden.paragraphText(alert.blocks.first ?? .thematicBreak), "Body text.")
        }
    }

    /// Alert recognition is case-insensitive, matching GitHub.
    func testAlertMarkerIsCaseInsensitive() {
        let blocks = Golden.lex("> [!warning]\n> careful\n")
        guard case .alert(let alert) = blocks[0] else {
            return XCTFail("expected an alert")
        }
        XCTAssertEqual(alert.kind, .warning)
    }

    /// An ordinary block quote — even one that merely *mentions* a marker token in
    /// running text — must NOT be misclassified as an alert.
    func testNormalBlockQuoteNotMisclassified() {
        // Plain quote.
        guard case .blockQuote = Golden.lex("> just a normal quote\n")[0] else {
            return XCTFail("plain quote should stay a block quote")
        }
        // Marker is not the whole first line ⇒ ordinary quote.
        guard case .blockQuote = Golden.lex("> [!NOTE] see below\n> more\n")[0] else {
            return XCTFail("inline marker mention should stay a block quote")
        }
        // Unknown alert type ⇒ ordinary quote.
        guard case .blockQuote = Golden.lex("> [!HINT]\n> body\n")[0] else {
            return XCTFail("unknown marker should stay a block quote")
        }
        // Bracketed text that is not a marker ⇒ ordinary quote.
        guard case .blockQuote = Golden.lex("> [note] without bang\n")[0] else {
            return XCTFail("non-marker bracket should stay a block quote")
        }
    }

    /// An alert may contain richer nested content (a list after the marker).
    func testAlertCarriesNestedBlocks() {
        let blocks = Golden.lex("> [!TIP]\n> Try this:\n>\n> - one\n> - two\n")
        guard case .alert(let alert) = blocks[0] else {
            return XCTFail("expected an alert")
        }
        XCTAssertEqual(alert.kind, .tip)
        let hasList = alert.blocks.contains { if case .list = $0 { return true }; return false }
        XCTAssertTrue(hasList, "alert body should contain the nested list")
    }

    // MARK: - Footnote definitions

    /// A `[^id]: text` line parses to a ``FootnoteDefinition`` with the id stripped
    /// of its brackets and the text as the definition body.
    func testFootnoteDefinitionParsed() {
        let blocks = Golden.lex("[^1]: A footnote body.\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .footnoteDefinition(let def) = blocks[0] else {
            return XCTFail("expected a footnote definition, got \(blocks[0])")
        }
        XCTAssertEqual(def.marker, "1")
        XCTAssertEqual(Golden.paragraphText(def.blocks.first ?? .thematicBreak), "A footnote body.")
    }

    /// A non-numeric label is preserved verbatim.
    func testFootnoteDefinitionNamedLabel() {
        let blocks = Golden.lex("[^note]: Named footnote.\n")
        guard case .footnoteDefinition(let def) = blocks[0] else {
            return XCTFail("expected a footnote definition")
        }
        XCTAssertEqual(def.marker, "note")
    }

    /// A bracketed line that is not a footnote definition (no colon) is NOT
    /// misclassified — it stays an ordinary paragraph.
    func testNonFootnoteBracketStaysParagraph() {
        let blocks = Golden.lex("[^1] is a bare reference, not a definition.\n")
        guard case .paragraph = blocks[0] else {
            return XCTFail("a reference without `:` should be a paragraph")
        }
    }

    // MARK: - Reference ↔ definition round-trip

    /// A `[^id]` inline reference parses to a ``Citation`` with a `nil` index, and
    /// a document containing both the reference and its `[^id]:` definition
    /// round-trips: the paragraph keeps the reference citation and the definition
    /// becomes a ``FootnoteDefinition`` with the same marker.
    func testFootnoteReferenceAndDefinitionRoundTrip() {
        let source = "Here is a reference[^note].\n\n[^note]: The definition text.\n"
        let raw = Golden.lex(source)
        let resolved = InlineParser.resolveInlines(in: raw, config: .default)

        XCTAssertEqual(resolved.count, 2)

        // The paragraph carries the footnote reference as a nil-index citation.
        guard case .paragraph(let para) = resolved[0] else {
            return XCTFail("expected a paragraph first")
        }
        let citation = para.inlines.compactMap { inline -> Citation? in
            if case .citation(let c) = inline { return c }
            return nil
        }.first
        XCTAssertEqual(citation?.marker, "note")
        XCTAssertNil(citation?.index, "a `[^id]` reference must have a nil index")

        // The definition round-trips with the matching marker.
        guard case .footnoteDefinition(let def) = resolved[1] else {
            return XCTFail("expected a footnote definition second")
        }
        XCTAssertEqual(def.marker, "note")
        XCTAssertEqual(Golden.paragraphText(def.blocks.first ?? .thematicBreak), "The definition text.")
    }
}
