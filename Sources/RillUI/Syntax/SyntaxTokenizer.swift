import Foundation

/// A small, single-pass lexical tokenizer that classifies source text against a
/// ``Grammar`` into ``SyntaxToken``s.
///
/// The tokenizer recognizes, in priority order at each position: comments
/// (block then line), string/character literals (honoring escapes), numeric
/// literals, identifiers (promoted to ``SyntaxTokenKind/keyword`` when in the
/// grammar's keyword set), and — in markup mode — HTML tag names. Everything
/// else accumulates into ``SyntaxTokenKind/plain`` runs. The concatenation of
/// every emitted token's `text` reproduces the input exactly, so a highlighter
/// built on it never alters the source.
///
/// It is a pure value with no stored state across calls; all work happens inside
/// ``tokenize(_:)`` over a local cursor, making it safe to run off the main
/// thread from any isolation.
struct SyntaxTokenizer: Sendable {
    /// The grammar driving classification.
    let grammar: Grammar

    /// Creates a tokenizer for a grammar.
    /// - Parameter grammar: The language description to classify against.
    init(grammar: Grammar) {
        self.grammar = grammar
    }

    /// Tokenizes `code` into a verbatim-preserving sequence of classified spans.
    /// - Parameter code: The source to classify.
    /// - Returns: The ordered tokens; concatenating their `text` equals `code`.
    func tokenize(_ code: String) -> [SyntaxToken] {
        let chars = Array(code)
        var tokens: [SyntaxToken] = []
        var index = 0
        // Accumulated unclassified characters, flushed as one `.plain` token.
        var plain: [Character] = []

        func flushPlain() {
            guard !plain.isEmpty else { return }
            tokens.append(SyntaxToken(text: String(plain), kind: .plain))
            plain.removeAll(keepingCapacity: true)
        }

        func emit(_ text: String, _ kind: SyntaxTokenKind) {
            flushPlain()
            tokens.append(SyntaxToken(text: text, kind: kind))
        }

        while index < chars.count {
            // 1. Comments (block comments matched before line comments so a `/*`
            //    is never mistaken for a `//`-prefixed line comment).
            if let (text, next) = matchComment(chars, at: index) {
                emit(text, .comment)
                index = next
                continue
            }

            // 2. Markup tags (HTML): `<tag …>` colors the tag name as a keyword.
            if grammar.isMarkup, chars[index] == "<",
               let (segment, next) = matchMarkupTag(chars, at: index) {
                flushPlain()
                tokens.append(contentsOf: segment)
                index = next
                continue
            }

            // 3. String / character literals.
            if let (text, next) = matchString(chars, at: index) {
                emit(text, .string)
                index = next
                continue
            }

            // 4. Numeric literals (only when not glued to an identifier head).
            if isNumberStart(chars, at: index) {
                let (text, next) = matchNumber(chars, at: index)
                emit(text, .number)
                index = next
                continue
            }

            // 5. Identifiers / keywords.
            if isIdentifierStart(chars[index]) {
                let (text, next) = matchIdentifier(chars, at: index)
                if grammar.keywords.contains(text) {
                    emit(text, .keyword)
                } else {
                    plain.append(contentsOf: text)
                }
                index = next
                continue
            }

            // 6. Anything else is plain.
            plain.append(chars[index])
            index += 1
        }

        flushPlain()
        return tokens
    }

    // MARK: - Comments

    /// Matches a comment opening at `index`. Block comments consume to their
    /// closer (or end of input if unterminated, so a streaming partial comment
    /// still highlights); line comments consume to end of line.
    private func matchComment(_ chars: [Character], at index: Int) -> (String, Int)? {
        // Try block comments first, then line comments; among each, longest
        // opener wins so `<!--` beats a hypothetical `<`.
        let ordered = grammar.comments.sorted { lhs, rhs in
            // Block (has close) before line; then by opener length descending.
            if (lhs.close != nil) != (rhs.close != nil) {
                return lhs.close != nil
            }
            return lhs.open.count > rhs.open.count
        }
        for comment in ordered {
            let open = Array(comment.open)
            guard matches(chars, at: index, prefix: open) else { continue }
            if let closeStr = comment.close {
                let close = Array(closeStr)
                var cursor = index + open.count
                while cursor < chars.count {
                    if matches(chars, at: cursor, prefix: close) {
                        let end = cursor + close.count
                        return (String(chars[index..<end]), end)
                    }
                    cursor += 1
                }
                // Unterminated block comment: take the rest.
                return (String(chars[index...]), chars.count)
            } else {
                // Line comment: to end of line (newline stays plain).
                var cursor = index + open.count
                while cursor < chars.count, chars[cursor] != "\n" {
                    cursor += 1
                }
                return (String(chars[index..<cursor]), cursor)
            }
        }
        return nil
    }

    // MARK: - Strings

    /// Matches a string/character literal opening at `index`, consuming through
    /// the matching closer (honoring escapes) or to end of input/line if
    /// unterminated.
    private func matchString(_ chars: [Character], at index: Int) -> (String, Int)? {
        for syntax in grammar.strings where chars[index] == syntax.open {
            var cursor = index + 1
            while cursor < chars.count {
                let c = chars[cursor]
                if syntax.allowsEscapes, c == "\\" {
                    cursor += 2
                    continue
                }
                if c == syntax.close {
                    let end = cursor + 1
                    return (String(chars[index..<end]), end)
                }
                // A literal newline terminates an unterminated single-line string
                // so a stray quote does not swallow the rest of the file.
                if c == "\n" {
                    return (String(chars[index..<cursor]), cursor)
                }
                cursor += 1
            }
            // Unterminated to end of input.
            return (String(chars[index...]), chars.count)
        }
        return nil
    }

    // MARK: - Numbers

    /// Whether a numeric literal can start at `index`. A digit always can; a
    /// leading `.` followed by a digit (e.g. `.5`) can too, but only when not
    /// part of a preceding identifier/number.
    private func isNumberStart(_ chars: [Character], at index: Int) -> Bool {
        let c = chars[index]
        if c.isNumber { return true }
        if c == ".", index + 1 < chars.count, chars[index + 1].isNumber {
            return true
        }
        return false
    }

    /// Matches a numeric literal: an optional radix prefix, digits, separators,
    /// a fractional part, and an exponent. Deliberately permissive — it colors
    /// what reads as a number without validating the grammar of every base.
    private func matchNumber(_ chars: [Character], at index: Int) -> (String, Int) {
        var cursor = index
        // Hex / binary / octal prefixes.
        if chars[cursor] == "0", cursor + 1 < chars.count {
            let radix = chars[cursor + 1]
            if radix == "x" || radix == "X" || radix == "b" || radix == "B"
                || radix == "o" || radix == "O" {
                cursor += 2
                while cursor < chars.count, isNumberBody(chars[cursor]) || isHexDigit(chars[cursor]) {
                    cursor += 1
                }
                return (String(chars[index..<cursor]), cursor)
            }
        }
        while cursor < chars.count {
            let c = chars[cursor]
            if c.isNumber || c == "_" {
                cursor += 1
            } else if c == ".", cursor + 1 < chars.count, chars[cursor + 1].isNumber {
                cursor += 1
            } else if c == "e" || c == "E" {
                // Exponent, with optional sign.
                var look = cursor + 1
                if look < chars.count, chars[look] == "+" || chars[look] == "-" {
                    look += 1
                }
                if look < chars.count, chars[look].isNumber {
                    cursor = look
                } else {
                    break
                }
            } else {
                break
            }
        }
        return (String(chars[index..<cursor]), cursor)
    }

    private func isNumberBody(_ c: Character) -> Bool {
        c.isNumber || c == "_" || c == "."
    }

    private func isHexDigit(_ c: Character) -> Bool {
        c.isHexDigit
    }

    // MARK: - Identifiers

    private func isIdentifierStart(_ c: Character) -> Bool {
        c == "_" || c == "$" || c.isLetter
    }

    private func isIdentifierBody(_ c: Character) -> Bool {
        c == "_" || c == "$" || c.isLetter || c.isNumber
    }

    /// Matches a maximal identifier run starting at `index`.
    private func matchIdentifier(_ chars: [Character], at index: Int) -> (String, Int) {
        var cursor = index + 1
        while cursor < chars.count, isIdentifierBody(chars[cursor]) {
            cursor += 1
        }
        return (String(chars[index..<cursor]), cursor)
    }

    // MARK: - Markup

    /// Matches an HTML tag `<…>` starting at `<`, returning sub-tokens that color
    /// the tag name as a keyword and the rest as plain, plus the index past `>`.
    /// Returns `nil` for `<!-- -->` (handled as a comment) and bare `<`.
    private func matchMarkupTag(_ chars: [Character], at index: Int) -> ([SyntaxToken], Int)? {
        // Comments are handled earlier; guard against `<!--`.
        if matches(chars, at: index, prefix: Array("<!--")) {
            return nil
        }
        var cursor = index + 1
        // Optional closing-tag slash or `!` for declarations.
        var prefix = "<"
        if cursor < chars.count, chars[cursor] == "/" || chars[cursor] == "!" {
            prefix.append(chars[cursor])
            cursor += 1
        }
        // The tag name.
        let nameStart = cursor
        while cursor < chars.count, isTagNameChar(chars[cursor]) {
            cursor += 1
        }
        guard cursor > nameStart else { return nil }
        let name = String(chars[nameStart..<cursor])

        // Consume the remainder of the tag up to and including `>`, classifying
        // any quoted attribute values as strings.
        var bodyTokens: [SyntaxToken] = []
        var bodyPlain: [Character] = []
        func flushBodyPlain() {
            guard !bodyPlain.isEmpty else { return }
            bodyTokens.append(SyntaxToken(text: String(bodyPlain), kind: .plain))
            bodyPlain.removeAll(keepingCapacity: true)
        }
        while cursor < chars.count {
            let c = chars[cursor]
            if c == ">" {
                bodyPlain.append(c)
                cursor += 1
                break
            }
            if c == "\"" || c == "'" {
                flushBodyPlain()
                if let (text, next) = matchString(chars, at: cursor) {
                    bodyTokens.append(SyntaxToken(text: text, kind: .string))
                    cursor = next
                    continue
                }
            }
            bodyPlain.append(c)
            cursor += 1
        }
        flushBodyPlain()

        var tokens: [SyntaxToken] = [
            SyntaxToken(text: prefix, kind: .plain),
            SyntaxToken(text: name, kind: .keyword),
        ]
        tokens.append(contentsOf: bodyTokens)
        return (tokens, cursor)
    }

    private func isTagNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == ":"
    }

    // MARK: - Utilities

    /// Whether `prefix` matches `chars` starting at `index`.
    private func matches(_ chars: [Character], at index: Int, prefix: [Character]) -> Bool {
        guard index + prefix.count <= chars.count else { return false }
        for offset in 0..<prefix.count where chars[index + offset] != prefix[offset] {
            return false
        }
        return true
    }
}
