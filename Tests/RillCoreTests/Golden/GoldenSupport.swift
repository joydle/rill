import XCTest
@testable import RillCore

/// Shared helpers for the block-lexer golden tests.
enum Golden {
    /// Lexes a Swift string by feeding its full UTF-8 byte buffer to ``BlockLexer``.
    static func lex(_ source: String) -> [Block] {
        let bytes = Array(source.utf8)
        return BlockLexer.lex(bytes[...])
    }

    /// Returns the raw text of a paragraph (its single ``Inline/text`` payload),
    /// or `nil` when the block is not a single-text paragraph.
    static func paragraphText(_ block: Block) -> String? {
        guard case .paragraph(let p) = block else { return nil }
        return rawText(p.inlines)
    }

    /// Concatenates the raw ``Inline/text`` payloads of a deferred inline span.
    static func rawText(_ inlines: [Inline]) -> String {
        inlines.map { inline -> String in
            if case .text(let s) = inline { return s }
            return ""
        }.joined()
    }
}
