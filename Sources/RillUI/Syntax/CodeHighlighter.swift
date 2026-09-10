import SwiftUI

/// Lowers a block of source code into a colorized `AttributedString`.
///
/// A `CodeHighlighter` is the pluggable seam RillUI uses to syntax-highlight
/// fenced code blocks. The default implementation is ``RillSyntax``; hosts can
/// supply their own conformer to reuse an existing highlighter (for example
/// a host can fold its own highlighter in as a conformer).
///
/// Implementations MUST preserve the source text verbatim — highlighting only
/// adds attributes (colors, the code font), never inserts, drops, or reorders
/// characters — so the rendered code is always faithful to what the model
/// emitted. Conformers should be cheap to call repeatedly during streaming;
/// ``RillSyntax`` memoizes by code and language.
public protocol CodeHighlighter: Sendable {
    /// Highlights `code`, tinting tokens according to `language`.
    ///
    /// - Parameters:
    ///   - code: The verbatim source to highlight.
    ///   - language: The fenced-code language tag (e.g. `"swift"`, `"json"`), or
    ///     `nil`/an unknown value to use a language-agnostic generic tokenizer.
    /// - Returns: An attributed copy of `code` whose runs carry token colors and
    ///   the code font.
    func highlight(_ code: String, language: String?) -> AttributedString
}

/// The coarse token classes a ``CodeHighlighter`` distinguishes.
///
/// Highlighting is intentionally shallow — a few classes shared across every
/// supported language — so it stays fast enough to run on every streamed
/// commit. Each kind maps to one slot of ``RillTheme/SyntaxColors``.
public enum SyntaxTokenKind: Sendable, Hashable {
    /// A reserved word, or, for markup, a tag name. Also used for
    /// boolean/null literals (`true`, `false`, `null`).
    case keyword
    /// A string or character literal, including its delimiters.
    case string
    /// A line or block comment, including its markers.
    case comment
    /// A numeric literal.
    case number
    /// Ordinary, unclassified text (identifiers, operators, whitespace).
    case plain

    /// The theme palette color for this token kind.
    /// - Parameter palette: The syntax palette to read from.
    /// - Returns: The matching color.
    public func color(in palette: RillTheme.SyntaxColors) -> Color {
        switch self {
        case .keyword: return palette.keyword
        case .string: return palette.string
        case .comment: return palette.comment
        case .number: return palette.number
        case .plain: return palette.plain
        }
    }
}

/// A classified, contiguous span of source text produced by a tokenizer.
///
/// Tokens partition the source: concatenating every token's `text` in order
/// reproduces the original code exactly. This is the unit ``RillSyntax`` colors.
public struct SyntaxToken: Sendable, Hashable {
    /// The verbatim source covered by this token.
    public var text: String
    /// The token's classification.
    public var kind: SyntaxTokenKind

    /// Creates a token.
    /// - Parameters:
    ///   - text: The verbatim source span.
    ///   - kind: The classification.
    public init(text: String, kind: SyntaxTokenKind) {
        self.text = text
        self.kind = kind
    }
}
