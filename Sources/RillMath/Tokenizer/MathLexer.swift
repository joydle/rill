/// A stateless lexer that turns a LaTeX math string into ``MathToken`` values.
///
/// The lexer is intentionally forgiving: it never throws and never fails on
/// malformed input, mirroring Rill's graceful-degradation contract. Unknown
/// control sequences are tokenized as ``MathToken/command(_:)`` and resolved
/// later by ``MathCommandTable`` / ``MathParser``.
public enum MathLexer: Sendable {

    /// Tokenizes `source` into a flat array of ``MathToken`` values.
    ///
    /// Whitespace between tokens is discarded. A backslash followed by a
    /// non-letter (e.g. `\,`, `\!`, `\{`, `\\`) is lexed as a single-character
    /// command — except `\\`, which becomes ``MathToken/doubleBackslash``.
    ///
    /// - Parameter source: The raw LaTeX fragment (without surrounding `$`).
    /// - Returns: The token stream, in source order.
    public static func tokenize(_ source: String) -> [MathToken] {
        tokenizeWithRanges(source).tokens
    }

    /// Tokenizes `source`, additionally returning each token's source span (in
    /// scalar-index space) and the decoded scalar array.
    ///
    /// Whitespace between tokens is still collapsed away (no token is emitted for
    /// it), but because each emitted token carries its source range, a consumer
    /// can recover the *verbatim* source between two tokens — spaces and all. The
    /// parser uses this to read the raw body of a `\text{…}` argument so that
    /// significant spaces inside text are preserved.
    ///
    /// - Parameter source: The raw LaTeX fragment (without surrounding `$`).
    /// - Returns: The token stream, a parallel array of each token's
    ///   `Range<Int>` in `scalars`, and the decoded `scalars`.
    static func tokenizeWithRanges(
        _ source: String
    ) -> (tokens: [MathToken], ranges: [Range<Int>], scalars: [Unicode.Scalar]) {
        var tokens: [MathToken] = []
        var ranges: [Range<Int>] = []
        let scalars = Array(source.unicodeScalars)
        var i = 0
        let n = scalars.count

        func emit(_ token: MathToken, from start: Int) {
            tokens.append(token)
            ranges.append(start..<i)
        }

        while i < n {
            let start = i
            let c = scalars[i]

            switch c {
            case "\\":
                i += 1
                guard i < n else {
                    // Trailing lone backslash: emit as a literal symbol.
                    emit(.symbol("\\"), from: start)
                    break
                }
                let next = scalars[i]
                if next == "\\" {
                    i += 1
                    emit(.doubleBackslash, from: start)
                } else if isLetter(next) {
                    var name = ""
                    while i < n, isLetter(scalars[i]) {
                        name.unicodeScalars.append(scalars[i])
                        i += 1
                    }
                    emit(.command(name), from: start)
                } else {
                    // Single-character control sequence (e.g. \, \! \{ \} \%).
                    i += 1
                    emit(.command(String(next)), from: start)
                }

            case "{":
                i += 1; emit(.leftBrace, from: start)
            case "}":
                i += 1; emit(.rightBrace, from: start)
            case "[":
                i += 1; emit(.leftBracket, from: start)
            case "]":
                i += 1; emit(.rightBracket, from: start)
            case "^":
                i += 1; emit(.superscript, from: start)
            case "_":
                i += 1; emit(.subscript, from: start)
            case "&":
                i += 1; emit(.ampersand, from: start)

            default:
                if isWhitespace(c) {
                    i += 1
                } else {
                    i += 1
                    emit(.symbol(String(c)), from: start)
                }
            }
        }

        return (tokens, ranges, scalars)
    }

    /// Whether a scalar is an ASCII letter — the only characters allowed in a
    /// multi-character LaTeX control-sequence name.
    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
    }

    /// Whether a scalar is insignificant whitespace to be discarded.
    private static func isWhitespace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r"
    }
}
