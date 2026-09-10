/// A single lexical unit produced by ``MathLexer`` from a LaTeX math string.
///
/// Tokens are deliberately coarse: structural punctuation (`{`, `}`, `[`, `]`,
/// `^`, `_`, `&`, `\\`) gets dedicated cases, control sequences become
/// ``command(_:)`` (carrying the name without the leading backslash), and every
/// other run of source maps to ``symbol(_:)``. Whitespace is collapsed away by
/// the lexer; explicit LaTeX spacing such as `\,` survives as a ``command(_:)``.
public enum MathToken: Sendable, Hashable {
    /// A control sequence, stored without its leading backslash (e.g. `frac`).
    case command(String)
    /// A single literal character to be rendered as-is (letters, digits,
    /// operators, parentheses).
    case symbol(String)
    /// `{` — opens a group.
    case leftBrace
    /// `}` — closes a group.
    case rightBrace
    /// `[` — opens an optional argument.
    case leftBracket
    /// `]` — closes an optional argument.
    case rightBracket
    /// `^` — superscript marker.
    case superscript
    /// `_` — subscript marker.
    case `subscript`
    /// `&` — column separator inside an environment.
    case ampersand
    /// `\\` — row separator inside an environment.
    case doubleBackslash
}
