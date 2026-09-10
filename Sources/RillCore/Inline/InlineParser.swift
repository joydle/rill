/// The inline parser: turns a block's raw text into a tree of ``Inline`` nodes.
///
/// `InlineParser` implements the CommonMark inline algorithm over the practical
/// GFM subset Rill targets: emphasis (`*`/`_`), strong (`**`/`__`), combined
/// `***`, GFM strikethrough (`~~`), code spans (one or more backticks), links
/// (`[text](url "title")`), angle and bare-URL autolinks, images
/// (`![alt](url)`), inline math (`\( … \)` and `$ … $`), citations (`[1]` and
/// `[^id]`), and backslash escapes. Emphasis honors the CommonMark *flanking*
/// rules, including the intraword `_` restriction.
///
/// The parser is a pure function. Unbalanced delimiters that never find a
/// partner — for example a lone trailing `**` produced mid-stream — are emitted
/// as literal text, so a streaming tail never flickers between formatted and
/// unformatted renderings.
public enum InlineParser {
    /// Parses raw inline text into a tree of ``Inline`` nodes.
    ///
    /// - Parameters:
    ///   - text: The raw inline source (a block's deferred text span).
    ///   - config: The feature configuration controlling optional extensions.
    /// - Returns: The parsed inline nodes, or an empty array for empty input.
    public static func parse(_ text: Substring, config: ParseConfig) -> [Inline] {
        parse(text, config: config, depth: 0)
    }

    /// Upper bound on nested inline-link label recursion. Past this depth a label
    /// is emitted as literal text instead of recursing, so an adversarial run of
    /// nested brackets (e.g. `[[[[…]]]]`) cannot overflow the stack.
    static let maxNestingDepth = 48

    /// Depth-threaded entry point. Each nested link label re-parses its inner
    /// text one level deeper; beyond ``maxNestingDepth`` the text is returned
    /// verbatim rather than recursing further.
    static func parse(_ text: Substring, config: ParseConfig, depth: Int) -> [Inline] {
        guard !text.isEmpty else { return [] }
        guard depth < maxNestingDepth else { return [.text(String(text))] }
        var scanner = InlineScanner(text: text, config: config, depth: depth)
        scanner.run()
        return scanner.finish()
    }

    /// Replaces every block's deferred raw-text inline spans with fully parsed
    /// inline trees, recursing into containers (quotes, lists) and table cells.
    ///
    /// The block lexer leaves inline content as a single ``Inline/text`` span so
    /// the block grammar stays independent of the inline grammar. This pass wires
    /// those raw spans through ``parse(_:config:)`` so a finished ``Document``
    /// carries real inline arrays. Code, math, and HTML blocks are left untouched
    /// because their content is verbatim, not inline-formatted.
    ///
    /// - Parameters:
    ///   - blocks: The blocks to resolve, as produced by ``BlockLexer/lex(_:)``.
    ///   - config: The feature configuration controlling optional extensions.
    /// - Returns: The blocks with inline content fully parsed.
    public static func resolveInlines(in blocks: [Block], config: ParseConfig) -> [Block] {
        blocks.map { resolve($0, config: config) }
    }

    private static func resolve(_ block: Block, config: ParseConfig) -> Block {
        switch block {
        case .heading(let h):
            return .heading(Heading(level: h.level, inlines: reparse(h.inlines, config: config)))
        case .paragraph(let p):
            return .paragraph(Paragraph(inlines: reparse(p.inlines, config: config)))
        case .blockQuote(let bq):
            return .blockQuote(BlockQuote(blocks: resolveInlines(in: bq.blocks, config: config)))
        case .alert(let alert):
            return .alert(Alert(kind: alert.kind, blocks: resolveInlines(in: alert.blocks, config: config)))
        case .footnoteDefinition(let def):
            return .footnoteDefinition(
                FootnoteDefinition(marker: def.marker, blocks: resolveInlines(in: def.blocks, config: config))
            )
        case .list(let list):
            let items = list.items.map {
                ListItem(blocks: resolveInlines(in: $0.blocks, config: config), checkbox: $0.checkbox)
            }
            return .list(List(items: items, isOrdered: list.isOrdered, start: list.start, isTight: list.isTight))
        case .table(let table):
            let header = table.header.map { reparse($0, config: config) }
            let rows = table.rows.map { row in row.map { reparse($0, config: config) } }
            return .table(Table(header: header, rows: rows, alignments: table.alignments))
        case .codeBlock, .thematicBreak, .mathBlock, .htmlBlock:
            return block
        }
    }

    /// Re-parses a deferred inline span (a single raw `.text`) into real inlines.
    /// Spans that are already parsed (anything other than one lone `.text`) are
    /// returned unchanged, so the pass is idempotent.
    private static func reparse(_ inlines: [Inline], config: ParseConfig) -> [Inline] {
        guard inlines.count == 1, case .text(let raw) = inlines[0] else { return inlines }
        return parse(Substring(raw), config: config)
    }
}

// MARK: - Scanner

/// The single-pass inline scanner.
///
/// Phase 1 (`run`) walks the source left to right, emitting fully-resolved nodes
/// (text, code, links, images, math, autolinks, citations) and recording
/// emphasis-delimiter runs as placeholder text nodes plus stack entries. Phase 2
/// (`finish`) resolves the delimiter stack into emphasis/strong/strikethrough
/// spans and coalesces adjacent text.
private struct InlineScanner {
    private let chars: [Character]
    private let config: ParseConfig

    /// The growing node buffer. Delimiter runs are stored as `.text` of their
    /// literal characters and later rewritten in place during emphasis matching.
    private var nodes: [Inline] = []
    private var delimiters = DelimiterStack()
    private var pos = 0

    /// The inline-link recursion depth this scanner runs at (0 for the top level).
    private let depth: Int

    init(text: Substring, config: ParseConfig, depth: Int = 0) {
        self.chars = Array(text)
        self.config = config
        self.depth = depth
    }

    private var atEnd: Bool { pos >= chars.count }
    private func peek(_ offset: Int = 0) -> Character? {
        let i = pos + offset
        return (i >= 0 && i < chars.count) ? chars[i] : nil
    }

    // MARK: Phase 1

    mutating func run() {
        var pending = ""

        func flushPending() {
            if !pending.isEmpty {
                nodes.append(.text(pending))
                pending = ""
            }
        }

        while let c = peek() {
            switch c {
            case "\\":
                if peek(1) == "(" {
                    // Inline math `\( … \)` takes precedence over escaping `(`.
                    flushPending()
                    if !scanBackslashParenMath() {
                        // Fall back to treating `\(` as an escaped paren.
                        pending.append("(")
                        pos += 2
                    }
                } else if let next = peek(1), Self.isEscapable(next) {
                    pending.append(next)
                    pos += 2
                } else {
                    pending.append("\\")
                    pos += 1
                }

            case "`":
                flushPending()
                if !scanCodeSpan() { pending.append(contentsOf: takeBacktickRunLiteral()) }

            case "*", "_", "~":
                flushPending()
                scanDelimiterRun(c)

            case "[":
                flushPending()
                if !scanLinkOrCitation() { pending.append("["); pos += 1 }

            case "!":
                if peek(1) == "[" {
                    flushPending()
                    if !scanImage() { pending.append("!"); pos += 1 }
                } else {
                    pending.append("!"); pos += 1
                }

            case "<":
                flushPending()
                if !scanAngleAutolink() { pending.append("<"); pos += 1 }

            case "$":
                if config.dollarMath {
                    flushPending()
                    if !scanDollarMath() { pending.append("$"); pos += 1 }
                } else {
                    pending.append("$"); pos += 1
                }

            case "h":
                // Possible bare-URL autolink (http/https).
                if config.bareURLAutolinks, matchesBareURLStart() {
                    flushPending()
                    if !scanBareURL() { pending.append("h"); pos += 1 }
                } else {
                    pending.append("h"); pos += 1
                }

            default:
                pending.append(c)
                pos += 1
            }
        }
        flushPending()
    }

    // MARK: Escapes

    /// Trims leading/trailing whitespace without depending on Foundation.
    private static func trimWhitespace(_ s: String) -> String {
        var sub = Substring(s)
        while let f = sub.first, f.isWhitespace { sub = sub.dropFirst() }
        while let l = sub.last, l.isWhitespace { sub = sub.dropLast() }
        return String(sub)
    }

    private static func isEscapable(_ c: Character) -> Bool {
        // ASCII punctuation per CommonMark.
        "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(c)
    }

    // MARK: Code spans

    /// Attempts to scan a backtick code span starting at `pos`. On success
    /// appends a `.code` node and advances; otherwise leaves `pos` unchanged and
    /// returns `false`.
    private mutating func scanCodeSpan() -> Bool {
        let start = pos
        var open = 0
        while peek() == "`" { open += 1; pos += 1 }
        // Search for a closing run of exactly `open` backticks.
        var i = pos
        while i < chars.count {
            if chars[i] == "`" {
                var run = 0
                while i < chars.count, chars[i] == "`" { run += 1; i += 1 }
                if run == open {
                    var content = String(chars[pos..<(i - open)])
                    content = Self.normalizeCodeSpan(content)
                    nodes.append(.code(content))
                    pos = i
                    return true
                }
            } else {
                i += 1
            }
        }
        // No closing fence: not a code span.
        pos = start
        return false
    }

    /// Consumes a run of backticks as literal text (used when a code span fails
    /// to close).
    private mutating func takeBacktickRunLiteral() -> String {
        var s = ""
        while peek() == "`" { s.append("`"); pos += 1 }
        return s
    }

    /// Applies CommonMark code-span normalization: line endings to spaces, and a
    /// single surrounding space stripped when the content is not all spaces.
    private static func normalizeCodeSpan(_ raw: String) -> String {
        var s = String(raw.map { $0 == "\n" ? " " : $0 })
        if s.count >= 2, s.first == " ", s.last == " ", s.contains(where: { $0 != " " }) {
            s.removeFirst()
            s.removeLast()
        }
        return s
    }

    // MARK: Emphasis delimiter runs

    private mutating func scanDelimiterRun(_ char: Character) {
        if char == "~", !config.strikethrough {
            // Strikethrough disabled: treat tildes literally.
            var s = ""
            while peek() == "~" { s.append("~"); pos += 1 }
            nodes.append(.text(s))
            return
        }

        let before = pos > 0 ? chars[pos - 1] : nil
        var count = 0
        while peek() == char { count += 1; pos += 1 }
        let after = peek()

        let (canOpen, canClose) = Self.flanking(char: char, before: before, after: after)
        let startIndex = nodes.count
        nodes.append(.text(String(repeating: char, count: count)))
        delimiters.push(DelimiterRun(
            char: char, count: count, canOpen: canOpen, canClose: canClose, startIndex: startIndex
        ))
    }

    /// Computes CommonMark left/right-flanking for a delimiter run, applying the
    /// `_` intraword restriction (underscores cannot open/close inside a word).
    /// `~` follows the `*`-style (no intraword restriction) rules.
    private static func flanking(char: Character, before: Character?, after: Character?) -> (Bool, Bool) {
        let beforeWS = before == nil || before!.isWhitespace
        let afterWS = after == nil || after!.isWhitespace
        let beforePunct = before.map { isPunctuation($0) } ?? false
        let afterPunct = after.map { isPunctuation($0) } ?? false

        // Left-flanking: not followed by whitespace, and either not followed by
        // punctuation or preceded by whitespace/punctuation.
        let leftFlanking = !afterWS && (!afterPunct || beforeWS || beforePunct)
        // Right-flanking: not preceded by whitespace, and either not preceded by
        // punctuation or followed by whitespace/punctuation.
        let rightFlanking = !beforeWS && (!beforePunct || afterWS || afterPunct)

        if char == "_" {
            let canOpen = leftFlanking && (!rightFlanking || beforePunct)
            let canClose = rightFlanking && (!leftFlanking || afterPunct)
            return (canOpen, canClose)
        }
        // '*' and '~'
        return (leftFlanking, rightFlanking)
    }

    private static func isPunctuation(_ c: Character) -> Bool {
        c.isPunctuation || c.isSymbol
    }

    // MARK: Links, citations

    /// Scans `[` — either a citation (`[1]`, `[^id]`) or an inline link
    /// `[text](url "title")`. Returns `false` if neither matches.
    private mutating func scanLinkOrCitation() -> Bool {
        // Citation forms first (cheap, unambiguous).
        if config.citations, let n = scanCitation() {
            nodes.append(n)
            return true
        }
        return scanInlineLink(isImage: false)
    }

    /// Scans a citation `[1]` (numeric) or `[^id]` (footnote). Does not consume
    /// on failure.
    private mutating func scanCitation() -> Inline? {
        precondition(peek() == "[")
        let start = pos
        var i = pos + 1
        guard i < chars.count else { return nil }

        if chars[i] == "^" {
            // Footnote: [^id]
            i += 1
            var id = ""
            while i < chars.count, chars[i] != "]" {
                let ch = chars[i]
                guard ch != "[", ch != " " else { pos = start; return nil }
                id.append(ch)
                i += 1
            }
            guard i < chars.count, chars[i] == "]", !id.isEmpty else { return nil }
            pos = i + 1
            return .citation(Citation(marker: id, index: nil))
        }

        // Numeric: [123]
        var digits = ""
        while i < chars.count, chars[i].isNumber {
            digits.append(chars[i]); i += 1
        }
        guard !digits.isEmpty, i < chars.count, chars[i] == "]" else { return nil }
        // Must not be a link: a following '(' means this is link text, not a citation.
        if i + 1 < chars.count, chars[i + 1] == "(" { return nil }
        pos = i + 1
        return .citation(Citation(marker: digits, index: Int(digits)))
    }

    /// Scans an inline link/image: `[text](url "title")`. The label brackets must
    /// balance and the `(` must follow immediately after the `]`.
    private mutating func scanInlineLink(isImage: Bool) -> Bool {
        let start = pos
        // pos is at '[' (link) — for images the caller already consumed '!['.
        guard peek() == "[" else { pos = start; return false }
        pos += 1
        guard let label = scanBracketLabel() else { pos = start; return false }
        guard peek() == "(" else { pos = start; return false }
        pos += 1
        guard let dest = scanLinkDestinationAndTitle() else { pos = start; return false }

        if isImage {
            nodes.append(.image(Image(alt: label, url: dest.url, title: dest.title)))
        } else {
            let inner = InlineParser.parse(Substring(label), config: config, depth: depth + 1)
            nodes.append(.link(Link(inlines: inner, url: dest.url, title: dest.title)))
        }
        return true
    }

    /// Reads the text between balanced `[` … `]`, assuming `pos` is just past the
    /// opening `[`. Returns the raw label and leaves `pos` just past the `]`.
    private mutating func scanBracketLabel() -> String? {
        let start = pos
        var depth = 1
        var label = ""
        while pos < chars.count {
            // CommonMark caps a link label at 999 characters. Enforcing it also
            // bounds this forward scan, so a long run of unmatched `[` (each of
            // which would otherwise scan to end-of-input) stays linear overall
            // instead of quadratic.
            if pos - start > 999 { return nil }
            let c = chars[pos]
            if c == "\\", pos + 1 < chars.count, Self.isEscapable(chars[pos + 1]) {
                label.append(c)
                label.append(chars[pos + 1])
                pos += 2
                continue
            }
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 { pos += 1; return label }
            }
            label.append(c)
            pos += 1
        }
        return nil
    }

    /// Reads `url` or `url "title"` up to the closing `)`, assuming `pos` is just
    /// past the opening `(`. Leaves `pos` just past the `)`.
    private mutating func scanLinkDestinationAndTitle() -> (url: String, title: String?)? {
        // Skip leading whitespace.
        while peek() == " " { pos += 1 }
        var url = ""
        // Angle-bracketed destination <...>.
        if peek() == "<" {
            pos += 1
            while let c = peek(), c != ">" { url.append(c); pos += 1 }
            guard peek() == ">" else { return nil }
            pos += 1
        } else {
            while let c = peek(), c != ")", c != " ", !c.isWhitespace {
                url.append(c); pos += 1
            }
        }
        // Optional title.
        var title: String? = nil
        while peek() == " " { pos += 1 }
        if let q = peek(), q == "\"" || q == "'" {
            pos += 1
            var t = ""
            while let c = peek(), c != q { t.append(c); pos += 1 }
            guard peek() == q else { return nil }
            pos += 1
            title = t
        }
        while peek() == " " { pos += 1 }
        guard peek() == ")" else { return nil }
        pos += 1
        return (url, title)
    }

    // MARK: Images

    private mutating func scanImage() -> Bool {
        let start = pos
        // pos at '!', next is '['.
        pos += 1 // consume '!'
        if scanInlineLink(isImage: true) { return true }
        pos = start
        return false
    }

    // MARK: Autolinks

    /// Scans an angle autolink `<https://…>` or `<scheme:…>`. Returns `false`
    /// when the angle content is not a URI.
    private mutating func scanAngleAutolink() -> Bool {
        let start = pos
        pos += 1 // consume '<'
        var inner = ""
        while let c = peek(), c != ">", c != "<", !c.isWhitespace {
            inner.append(c); pos += 1
        }
        guard peek() == ">", Self.looksLikeURI(inner) else { pos = start; return false }
        pos += 1
        nodes.append(.link(Link(inlines: [.text(inner)], url: inner, title: nil)))
        return true
    }

    private static func looksLikeURI(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":") else { return false }
        let scheme = s[s.startIndex..<colon]
        guard scheme.count >= 2, scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else {
            return false
        }
        return s.index(after: colon) < s.endIndex
    }

    /// Whether the current position begins a bare `http://` / `https://` URL.
    private func matchesBareURLStart() -> Bool {
        if matchesLiteral("https://", at: pos) { return true }
        if matchesLiteral("http://", at: pos) { return true }
        return false
    }

    private func matchesLiteral(_ literal: String, at index: Int) -> Bool {
        let lit = Array(literal)
        guard index + lit.count <= chars.count else { return false }
        for k in 0..<lit.count where chars[index + k] != lit[k] { return false }
        return true
    }

    /// Scans a bare-URL autolink, stopping at whitespace and trimming trailing
    /// punctuation that is unlikely to belong to the URL.
    private mutating func scanBareURL() -> Bool {
        let start = pos
        var url = ""
        while let c = peek(), !c.isWhitespace, c != "<" {
            url.append(c); pos += 1
        }
        // Trim trailing punctuation (.,;:!?) and an unbalanced closing paren.
        while let lastCh = url.last {
            if ".,;:!?\"'".contains(lastCh) {
                url.removeLast(); pos -= 1
            } else if lastCh == ")" && url.filter({ $0 == "(" }).count < url.filter({ $0 == ")" }).count {
                url.removeLast(); pos -= 1
            } else {
                break
            }
        }
        // Require a host after the scheme.
        guard url.count > "https://".count || url.count > "http://".count else { pos = start; return false }
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { pos = start; return false }
        let host = url.hasPrefix("https://") ? url.dropFirst(8) : url.dropFirst(7)
        guard !host.isEmpty, host.contains(".") else { pos = start; return false }
        nodes.append(.link(Link(inlines: [.text(url)], url: url, title: nil)))
        return true
    }

    // MARK: Math

    /// Scans `\( … \)` inline math. `pos` is at the backslash.
    private mutating func scanBackslashParenMath() -> Bool {
        let start = pos
        guard peek() == "\\", peek(1) == "(" else { return false }
        pos += 2
        var body = ""
        while pos < chars.count {
            if chars[pos] == "\\", pos + 1 < chars.count, chars[pos + 1] == ")" {
                pos += 2
                nodes.append(.mathInline(Self.trimWhitespace(body)))
                return true
            }
            body.append(chars[pos])
            pos += 1
        }
        pos = start
        return false
    }

    /// Scans `$ … $` inline math (single dollar). Avoids matching currency by
    /// requiring a non-space immediately inside the delimiters and a balanced
    /// closing `$` on the same span.
    private mutating func scanDollarMath() -> Bool {
        let start = pos
        guard peek() == "$" else { return false }
        // Not a double-dollar (that's block math, handled by the block lexer).
        if peek(1) == "$" { return false }
        // The char right after the opening '$' must not be whitespace or a digit
        // (so "$5" / "$ x" stay literal — currency / spaced text).
        guard let first = peek(1), !first.isWhitespace, !first.isNumber else { return false }
        pos += 1
        var body = ""
        while let c = peek() {
            if c == "\\", let n = peek(1) {
                body.append(c); body.append(n); pos += 2; continue
            }
            if c == "$" {
                // Closing '$' must not be preceded by whitespace.
                if body.last?.isWhitespace == true { break }
                pos += 1
                nodes.append(.mathInline(body))
                return true
            }
            if c == "\n" { break }
            body.append(c)
            pos += 1
        }
        pos = start
        return false
    }

    // MARK: Phase 2 — emphasis resolution & coalescing

    mutating func finish() -> [Inline] {
        resolveEmphasis()
        return Self.coalesce(nodes)
    }

    /// Resolves the delimiter stack into emphasis/strong/strikethrough spans
    /// using the CommonMark "process emphasis" algorithm (closer scans backward
    /// for the nearest matching opener). Leftover runs stay as literal text.
    private mutating func resolveEmphasis() {
        // Work over indices into `delimiters`, matching closers to openers.
        var closerIdx = 0
        while closerIdx < delimiters.count {
            let closer = delimiters[closerIdx]
            guard closer.canClose, closer.count > 0 else { closerIdx += 1; continue }

            // Find nearest opener before closer with same char that canOpen.
            var openerIdx = closerIdx - 1
            var found = false
            while openerIdx >= 0 {
                let opener = delimiters[openerIdx]
                if opener.char == closer.char, opener.canOpen, opener.count > 0 {
                    // CommonMark "rule of 3" for * and _ (multiple-of-3 restriction).
                    if !ruleOfThreeBlocks(opener: opener, closer: closer) {
                        found = true
                        break
                    }
                }
                openerIdx -= 1
            }

            guard found else { closerIdx += 1; continue }

            // CommonMark "process emphasis": once an opener/closer pair is
            // matched, every delimiter run strictly between them is removed from
            // the stack (it can never participate in a later match). Skipping
            // this step leaves stale inner runs whose `startIndex` is dragged
            // below zero by `wrap`'s buffer shift, and which can then be selected
            // as openers — driving a negative index into `nodes` and trapping.
            // Their literal placeholder text is already in the buffer (captured
            // into the wrapped span), so deactivating them keeps the text intact.
            if openerIdx + 1 < closerIdx {
                for k in (openerIdx + 1)..<closerIdx {
                    var inner = delimiters[k]
                    inner.count = 0
                    delimiters[k] = inner
                }
            }

            // Determine span size: 2 for strong/strike, else 1.
            let useStrike = closer.char == "~"
            let useCount: Int
            if useStrike {
                useCount = Swift.min(2, Swift.min(delimiters[openerIdx].count, closer.count))
            } else {
                useCount = (delimiters[openerIdx].count >= 2 && closer.count >= 2) ? 2 : 1
            }

            wrap(openerIdx: openerIdx, closerIdx: closerIdx, count: useCount, strike: useStrike)

            // Consume the used delimiters.
            var opener = delimiters[openerIdx]
            var newCloser = delimiters[closerIdx]
            opener.count -= useCount
            newCloser.count -= useCount
            delimiters[openerIdx] = opener
            delimiters[closerIdx] = newCloser

            // Update placeholder text for partially-consumed runs.
            updatePlaceholder(at: opener.startIndex, run: opener)
            updatePlaceholder(at: newCloser.startIndex, run: newCloser)

            if newCloser.count == 0 { closerIdx += 1 }
            // else: re-process same closer against earlier openers.
        }
    }

    private func ruleOfThreeBlocks(opener: DelimiterRun, closer: DelimiterRun) -> Bool {
        guard opener.char != "~" else { return false }
        // If either run can both open and close, sum of lengths multiple of 3
        // (and not both multiples of 3) blocks the match.
        let bothFunctional = (opener.canOpen && opener.canClose) || (closer.canOpen && closer.canClose)
        guard bothFunctional else { return false }
        let sum = opener.originalCount + closer.originalCount
        if sum % 3 == 0 {
            return !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
        }
        return false
    }

    /// Wraps the nodes strictly between the opener and closer placeholders into
    /// an emphasis/strong/strike inline, rewriting the buffer.
    private mutating func wrap(openerIdx: Int, closerIdx: Int, count: Int, strike: Bool) {
        let openerNodePos = delimiters[openerIdx].startIndex
        let closerNodePos = delimiters[closerIdx].startIndex
        // Inner content is nodes strictly between the two placeholder slots.
        // Defensive bounds clamp: corrupted indices must never index out of range.
        guard openerNodePos >= 0, closerNodePos <= nodes.count,
              openerNodePos + 1 <= closerNodePos else { return }
        let innerRange = (openerNodePos + 1)..<closerNodePos
        let inner = Array(nodes[innerRange])

        let wrapped: Inline
        if strike {
            wrapped = .strikethrough(inner)
        } else if count == 2 {
            wrapped = .strong(inner)
        } else {
            wrapped = .emphasis(inner)
        }

        // Replace inner range with the single wrapped node.
        nodes.replaceSubrange(innerRange, with: [wrapped])

        // The buffer shrank; shift every delimiter startIndex that pointed past
        // the inner range. The closer placeholder slot moves by delta.
        let removed = inner.count
        let delta = removed - 1 // replaced `removed` nodes with 1
        if delta != 0 {
            for k in delimiters.indices where delimiters[k].startIndex > openerNodePos {
                delimiters[k].startIndex -= delta
            }
        }
    }

    /// Rewrites a delimiter run's placeholder text to reflect the characters it
    /// still has after partial consumption (so leftovers render literally).
    private mutating func updatePlaceholder(at index: Int, run: DelimiterRun) {
        guard index >= 0, index < nodes.count else { return }
        nodes[index] = .text(String(repeating: run.char, count: run.count))
    }

    /// Merges adjacent `.text` nodes and drops empty ones, recursing into spans.
    static func coalesce(_ input: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for node in input {
            let normalized: Inline
            switch node {
            case .emphasis(let c): normalized = .emphasis(coalesce(c))
            case .strong(let c): normalized = .strong(coalesce(c))
            case .strikethrough(let c): normalized = .strikethrough(coalesce(c))
            default: normalized = node
            }
            if case .text(let s) = normalized {
                if s.isEmpty { continue }
                if case .text(let prev)? = out.last {
                    out[out.count - 1] = .text(prev + s)
                    continue
                }
            }
            out.append(normalized)
        }
        return out
    }
}

