/// Parses a LaTeX math string into a ``MathNode`` tree.
///
/// The parser is a hand-rolled recursive-descent pass over the ``MathToken``
/// stream from ``MathLexer``. It resolves control sequences through
/// ``MathCommandTable``, builds structural nodes (fractions, radicals, scripts,
/// big operators, delimited groups, matrices, accents), and degrades any
/// unmapped command to ``MathNode/unknown(_:)``. It never throws.
public enum MathParser: Sendable {

    /// Parses `source` into an array of top-level ``MathNode`` values.
    /// - Parameter source: A LaTeX math fragment (without surrounding `$`).
    /// - Returns: The parsed node list; `[]` for empty input.
    public static func parse(_ source: String) -> [MathNode] {
        let lexed = MathLexer.tokenizeWithRanges(source)
        var state = State(tokens: lexed.tokens, ranges: lexed.ranges, scalars: lexed.scalars)
        return state.parseSequence(until: { _ in false })
    }

    /// Mutable cursor over the token stream with the recursive-descent grammar.
    private struct State {
        let tokens: [MathToken]
        /// Each token's source span (in `scalars` index space), parallel to
        /// `tokens`. Used to recover verbatim source for `\text{…}`.
        let ranges: [Range<Int>]
        /// The decoded source scalars, used to read raw text-argument spans.
        let scalars: [Unicode.Scalar]
        var index = 0

        var current: MathToken? { index < tokens.count ? tokens[index] : nil }

        mutating func advance() { index += 1 }

        /// Parses a run of nodes, attaching scripts, until `stop` matches the
        /// current token (which is left unconsumed) or the stream ends.
        mutating func parseSequence(until stop: (MathToken) -> Bool) -> [MathNode] {
            var nodes: [MathNode] = []
            while let tok = current, !stop(tok) {
                guard let atom = parseAtom() else { break }
                let node = attachScripts(to: atom)
                nodes.append(node)
            }
            return nodes
        }

        /// If the next tokens are `^`/`_` scripts, wraps `base` in a
        /// ``MathNode/scripts(base:sup:sub:)`` node (handling either order).
        mutating func attachScripts(to base: MathNode) -> MathNode {
            var sup: [MathNode]? = nil
            var sub: [MathNode]? = nil

            while let tok = current, tok == .superscript || tok == .subscript {
                advance()
                let arg = parseScriptArgument()
                if tok == .superscript { sup = arg } else { sub = arg }
            }

            guard sup != nil || sub != nil else { return base }
            return .scripts(base: [base], sup: sup, sub: sub)
        }

        /// Parses the argument of a `^`/`_`: either a braced group or a single
        /// atom.
        mutating func parseScriptArgument() -> [MathNode] {
            guard let tok = current else { return [] }
            if tok == .leftBrace {
                advance()
                let body = parseSequence(until: { $0 == .rightBrace })
                if current == .rightBrace { advance() }
                return body
            }
            if let atom = parseAtom() { return [atom] }
            return []
        }

        /// Parses one atomic construct (symbol, group, command, …), not yet
        /// considering trailing scripts.
        mutating func parseAtom() -> MathNode? {
            // Skip any run of stray structural tokens iteratively. Recursing here
            // would grow the stack linearly in the run length, so a long burst of
            // malformed input (e.g. `}}}}…`, `&&&&…`, or `\\\\…` arriving
            // mid-stream) could overflow the stack and crash, violating the
            // never-crash contract. A loop bounds depth to genuine nesting only.
            while let tok = current {
                switch tok {
                case .symbol(let s):
                    advance()
                    return .symbol(s)

                case .leftBrace:
                    advance()
                    let body = parseSequence(until: { $0 == .rightBrace })
                    if current == .rightBrace { advance() }
                    return .group(body)

                case .command(let name):
                    advance()
                    return parseCommand(name)

                case .rightBrace, .rightBracket, .leftBracket,
                     .superscript, .subscript, .ampersand, .doubleBackslash:
                    // Stray structural token outside its construct: skip it and
                    // continue scanning for the next real atom.
                    advance()
                    continue
                }
            }
            return nil
        }

        /// Dispatches a control sequence to its structural handler or resolves
        /// it through ``MathCommandTable``.
        mutating func parseCommand(_ name: String) -> MathNode {
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac":
                let num = parseGroupArgument()
                let den = parseGroupArgument()
                return .frac(numerator: num, denominator: den)

            case "binom", "dbinom", "tbinom":
                // Render binomials as a parenthesized fraction-like stack; model
                // as a delimited fraction so layout can stack the arguments.
                let top = parseGroupArgument()
                let bottom = parseGroupArgument()
                return .delimited(
                    left: "(",
                    right: ")",
                    body: [.frac(numerator: top, denominator: bottom)]
                )

            case "sqrt":
                var indexArg: [MathNode]? = nil
                if current == .leftBracket {
                    advance()
                    indexArg = parseSequence(until: { $0 == .rightBracket })
                    if current == .rightBracket { advance() }
                }
                let radicand = parseGroupArgument()
                return .sqrt(index: indexArg, radicand: radicand)

            case "left":
                return parseDelimited()

            case "begin":
                return parseEnvironment()

            default:
                guard let command = MathCommandTable.lookup(name) else {
                    return .unknown(name)
                }
                return resolve(name: name, command: command)
            }
        }

        /// Maps a resolved table entry to a concrete ``MathNode``, applying
        /// structural semantics for big operators, accents, fonts, and spacing.
        mutating func resolve(name: String, command: MathCommand) -> MathNode {
            switch command.category {
            case .bigOperator:
                let (lower, upper) = parseLimits()
                return .bigOp(op: command.symbol, lower: lower, upper: upper)

            case .accent:
                let base = parseGroupArgument()
                return .accent(kind: name, base: base)

            case .font:
                if name == "text" || name == "textrm" || name == "textbf"
                    || name == "textit" || name == "operatorname" {
                    return .text(rawTextArgument())
                }
                let body = parseGroupArgument()
                // Represent a styled run as a group; styling metadata is applied
                // downstream. Keep the structure for layout.
                return .group(body)

            case .space:
                return .space

            default:
                return .symbol(command.symbol)
            }
        }

        /// Parses optional `_{…}` / `^{…}` limits following a big operator, in
        /// either order.
        mutating func parseLimits() -> (lower: [MathNode]?, upper: [MathNode]?) {
            var lower: [MathNode]? = nil
            var upper: [MathNode]? = nil
            while let tok = current, tok == .superscript || tok == .subscript {
                advance()
                let arg = parseScriptArgument()
                if tok == .superscript { upper = arg } else { lower = arg }
            }
            return (lower, upper)
        }

        /// Parses a `\left … \right` delimited group.
        mutating func parseDelimited() -> MathNode {
            let left = parseDelimiterToken()
            let body = parseSequence(until: { token in
                if case .command("right") = token { return true }
                return false
            })
            // Consume the matching \right.
            var right = "."
            if case .command("right") = current {
                advance()
                right = parseDelimiterToken()
            }
            return .delimited(left: left, right: right, body: body)
        }

        /// Reads the delimiter glyph that follows `\left` or `\right`.
        mutating func parseDelimiterToken() -> String {
            guard let tok = current else { return "." }
            switch tok {
            case .symbol(let s):
                advance()
                return s == "." ? "." : s
            case .leftBracket:
                advance(); return "["
            case .rightBracket:
                advance(); return "]"
            case .command(let name):
                advance()
                if let cmd = MathCommandTable.lookup(name), cmd.category == .delimiter {
                    return cmd.symbol
                }
                return name
            default:
                advance()
                return "."
            }
        }

        /// Parses a `\begin{env} … \end{env}` matrix-family environment into a
        /// 2-D cell grid.
        mutating func parseEnvironment() -> MathNode {
            let env = rawBracedName()
            var rows: [[[MathNode]]] = []
            var currentRow: [[MathNode]] = []
            var cell: [MathNode] = []

            func flushCell() {
                currentRow.append(cell)
                cell = []
            }
            func flushRow() {
                flushCell()
                rows.append(currentRow)
                currentRow = []
            }

            loop: while let tok = current {
                switch tok {
                case .ampersand:
                    advance()
                    flushCell()
                case .doubleBackslash:
                    advance()
                    flushRow()
                case .command("end"):
                    advance()
                    _ = rawBracedName()
                    break loop
                default:
                    if let atom = parseAtom() {
                        cell.append(attachScripts(to: atom))
                    } else {
                        break loop
                    }
                }
            }

            // Flush any trailing cell/row that wasn't terminated by `\\`.
            if !cell.isEmpty || !currentRow.isEmpty {
                flushRow()
            }

            return .matrix(env: env, rows: rows)
        }

        /// Parses the next argument as a group: `{…}` body, or a single atom if
        /// unbraced.
        mutating func parseGroupArgument() -> [MathNode] {
            guard let tok = current else { return [] }
            if tok == .leftBrace {
                advance()
                let body = parseSequence(until: { $0 == .rightBrace })
                if current == .rightBrace { advance() }
                return body
            }
            if let atom = parseAtom() {
                return [attachScripts(to: atom)]
            }
            return []
        }

        /// Reads a `{name}` argument as a raw concatenated string (used for
        /// environment names).
        mutating func rawBracedName() -> String {
            guard current == .leftBrace else { return "" }
            advance()
            var name = ""
            while let tok = current, tok != .rightBrace {
                if case .symbol(let s) = tok { name += s }
                advance()
            }
            if current == .rightBrace { advance() }
            return name
        }

        /// Reads a `{…}` argument as raw text for `\text{…}`.
        ///
        /// The body is taken *verbatim from the source* between the opening and
        /// matching closing brace, so significant whitespace inside the text
        /// (e.g. `\text{a b}` → `"a b"`) and any embedded backslashes are
        /// preserved — the collapsed token stream alone could not recover them.
        mutating func rawTextArgument() -> String {
            guard current == .leftBrace, index < ranges.count else { return "" }
            // Source position immediately after the opening `{`.
            let bodyStart = ranges[index].upperBound
            advance()
            var depth = 1
            while index < tokens.count {
                switch tokens[index] {
                case .leftBrace:
                    depth += 1
                case .rightBrace:
                    depth -= 1
                    if depth == 0 {
                        let bodyEnd = ranges[index].lowerBound
                        advance()
                        return rawSource(bodyStart..<bodyEnd)
                    }
                default:
                    break
                }
                advance()
            }
            // Unterminated argument: take the rest of the source verbatim.
            return rawSource(bodyStart..<scalars.count)
        }

        /// Materializes a verbatim source span from the scalar buffer.
        private func rawSource(_ range: Range<Int>) -> String {
            guard range.lowerBound < range.upperBound,
                  range.lowerBound >= 0, range.upperBound <= scalars.count
            else { return "" }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[range])
            return String(view)
        }
    }
}
