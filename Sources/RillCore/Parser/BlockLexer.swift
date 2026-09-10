/// The block-structure lexer: turns a UTF-8 byte slice into an array of
/// top-level ``Block`` values.
///
/// `BlockLexer` parses *block* structure only — headings, paragraphs, quotes,
/// lists, code/math/HTML blocks, tables, and thematic breaks. Inline content
/// (emphasis, links, code spans, …) is **deferred**: each block's inline text is
/// kept verbatim as a single ``Inline/text`` payload to be re-parsed by a later
/// inline pass. This keeps the block grammar independent of the inline grammar
/// and lets the incremental engine re-lex the dirty tail cheaply.
///
/// The lexer is non-incremental and stateless: ``lex(_:)`` is a pure function of
/// its input. Open constructs at the end of input (an unterminated fence, an
/// unclosed math block) are surfaced with `isClosed == false` so the streaming
/// layer can keep them in the live tail.
public enum BlockLexer {
    /// Lexes the block structure of a UTF-8 byte slice into top-level blocks.
    ///
    /// - Parameter utf8: The source bytes (typically the parser's growing UTF-8
    ///   buffer, or a dirty-tail slice of it). The slice's own indices are
    ///   irrelevant to the result; only its contents matter.
    /// - Returns: The document's top-level blocks, in order. Inline content is
    ///   deferred as raw ``Inline/text`` spans.
    public static func lex(_ utf8: ArraySlice<UInt8>) -> [Block] {
        let lines = collectLines(utf8)
        var parser = BlockParser(lines: lines)
        return parser.parseBlocks(minIndent: 0)
    }

    /// Decodes every physical line of the slice into a ``RawLine`` for parsing.
    static func collectLines(_ utf8: ArraySlice<UInt8>) -> [RawLine] {
        var scanner = LineScanner(utf8)
        var result: [RawLine] = []
        while let line = scanner.next() {
            result.append(RawLine(text: String(decoding: line.bytes, as: UTF8.self)))
        }
        return result
    }
}

/// A decoded source line plus cached structural facts used during block parsing.
struct RawLine {
    /// The line's text, excluding its terminator.
    let text: String

    /// The number of leading space-equivalent columns (tabs count as up to 4).
    let indent: Int

    /// The line content with its leading indentation removed.
    let trimmed: Substring

    init(text: String) {
        self.text = text
        var col = 0
        var idx = text.startIndex
        while idx < text.endIndex {
            let c = text[idx]
            if c == " " {
                col += 1
            } else if c == "\t" {
                col += 4 - (col % 4)
            } else {
                break
            }
            idx = text.index(after: idx)
        }
        self.indent = col
        self.trimmed = text[idx...]
    }

    /// Whether the line is blank (empty or only whitespace).
    var isBlank: Bool { trimmed.isEmpty }
}

/// A recursive-descent block parser over a window of ``RawLine`` values.
///
/// The parser advances a cursor through the lines, dispatching each line to the
/// construct it opens. Container constructs (block quotes, list items) recurse by
/// stripping their marker/indent and re-running the block grammar on the inner
/// content.
private struct BlockParser {
    let lines: [RawLine]
    var cursor: Int = 0

    /// The container-nesting depth of this parser (0 at the document level). Each
    /// nested block quote / list item / footnote definition recurses one deeper.
    let depth: Int

    /// Maximum container-nesting depth. Past this, a would-be container line
    /// (block quote or list marker) is parsed as a plain paragraph instead of
    /// recursing, so an adversarial run of markers (`>>>…>` or deeply nested
    /// list items) cannot overflow the stack.
    static let maxNestingDepth = 48

    init(lines: [RawLine], depth: Int = 0) {
        self.lines = lines
        self.depth = depth
    }

    var atEnd: Bool { cursor >= lines.count }
    func peek() -> RawLine? { cursor < lines.count ? lines[cursor] : nil }

    /// Parses a run of blocks whose container contributes `minIndent` columns of
    /// indentation. Stops at end of input (callers that need early termination —
    /// quotes, list items — pre-slice their content instead).
    mutating func parseBlocks(minIndent: Int) -> [Block] {
        var blocks: [Block] = []
        while let line = peek() {
            if line.isBlank {
                cursor += 1
                continue
            }
            if let block = parseBlock(minIndent: minIndent) {
                blocks.append(block)
            } else {
                cursor += 1
            }
        }
        return blocks
    }

    /// Parses the single block beginning at the cursor, advancing past it.
    private mutating func parseBlock(minIndent: Int) -> Block? {
        guard let line = peek() else { return nil }
        let relIndent = line.indent - minIndent

        // Indented code block: 4+ columns past the container indent, and not a
        // continuation of a list/quote already stripped by the caller.
        if relIndent >= 4 {
            return parseIndentedCode(minIndent: minIndent)
        }

        let content = line.trimmed

        if content.hasPrefix(">") {
            if depth >= Self.maxNestingDepth { return parseParagraph(minIndent: minIndent) }
            return parseBlockQuote(minIndent: minIndent)
        }
        if let fence = FenceInfo(content) {
            return parseFencedCode(fence: fence, minIndent: minIndent)
        }
        if let math = MathFenceInfo(content) {
            return parseMathBlock(open: math, minIndent: minIndent)
        }
        if isThematicBreak(content) {
            cursor += 1
            return .thematicBreak
        }
        if let heading = parseATXHeading(content) {
            cursor += 1
            return .heading(heading)
        }
        if let marker = ListMarker(content) {
            if depth >= Self.maxNestingDepth { return parseParagraph(minIndent: minIndent) }
            return parseList(firstMarker: marker, minIndent: minIndent)
        }
        if isHTMLBlockStart(content) {
            return parseHTMLBlock(minIndent: minIndent)
        }
        if let footnote = FootnoteDefMarker(content) {
            // A footnote body is parsed recursively, so an adversarial chain like
            // `[^a]: [^b]: [^c]: …` would recurse one level per segment and
            // overflow the stack. Cap it exactly like block quotes and lists.
            if depth >= Self.maxNestingDepth { return parseParagraph(minIndent: minIndent) }
            return parseFootnoteDefinition(marker: footnote, minIndent: minIndent)
        }
        if isTableHeader(at: cursor) {
            return parseTable(minIndent: minIndent)
        }
        return parseParagraph(minIndent: minIndent)
    }

    // MARK: Paragraph

    private mutating func parseParagraph(minIndent: Int) -> Block {
        var texts: [String] = []
        while let line = peek(), !line.isBlank {
            let content = line.trimmed
            // A paragraph is interrupted by structural starts.
            if line.indent - minIndent < 4 {
                if content.hasPrefix(">")
                    || FenceInfo(content) != nil
                    || MathFenceInfo(content) != nil
                    || isThematicBreak(content)
                    || parseATXHeading(content) != nil
                    || ListMarker(content) != nil
                    || isHTMLBlockStart(content)
                {
                    if !texts.isEmpty { break }
                }
            }
            texts.append(String(content.trimmingChars(in: [" ", "\t"])))
            cursor += 1
        }
        let raw = texts.joined(separator: "\n")
        return .paragraph(Paragraph(inlines: deferredInlines(raw)))
    }

    // MARK: Headings

    private func parseATXHeading(_ content: Substring) -> Heading? {
        var level = 0
        var idx = content.startIndex
        while idx < content.endIndex, content[idx] == "#" {
            level += 1
            idx = content.index(after: idx)
        }
        guard level >= 1, level <= 6 else { return nil }
        // Require a space (or end of line) after the hashes.
        if idx < content.endIndex {
            guard content[idx] == " " || content[idx] == "\t" else { return nil }
        }
        var body = content[idx...]
        body = body.drop { $0 == " " || $0 == "\t" }
        // Strip an optional trailing run of hashes (closing sequence).
        var trimmed = Substring(body)
        while trimmed.last == " " || trimmed.last == "\t" {
            trimmed = trimmed.dropLast()
        }
        if trimmed.last == "#" {
            var t = trimmed
            while t.last == "#" { t = t.dropLast() }
            let beforeHashes = t
            if beforeHashes.isEmpty || beforeHashes.last == " " || beforeHashes.last == "\t" {
                trimmed = beforeHashes
                while trimmed.last == " " || trimmed.last == "\t" {
                    trimmed = trimmed.dropLast()
                }
            }
        }
        return Heading(level: level, inlines: deferredInlines(String(trimmed)))
    }

    // MARK: Thematic break

    private func isThematicBreak(_ content: Substring) -> Bool {
        var marker: Character? = nil
        var count = 0
        for c in content {
            if c == " " || c == "\t" { continue }
            if c == "-" || c == "*" || c == "_" {
                if let m = marker, m != c { return false }
                marker = c
                count += 1
            } else {
                return false
            }
        }
        return count >= 3
    }

    // MARK: Fenced code

    private mutating func parseFencedCode(fence: FenceInfo, minIndent: Int) -> Block {
        cursor += 1 // consume opening fence
        var content = ""
        var isClosed = false
        while let line = peek() {
            let stripped = stripIndent(line, upTo: minIndent)
            if let close = FenceInfo(Substring(stripped)),
               close.char == fence.char,
               close.length >= fence.length,
               close.info.isEmpty {
                cursor += 1
                isClosed = true
                break
            }
            content += stripped
            content += "\n"
            cursor += 1
        }
        let language = fence.info.isEmpty ? nil : String(fence.info)
        return .codeBlock(CodeBlock(language: language, content: content, isClosed: isClosed))
    }

    // MARK: Indented code

    private mutating func parseIndentedCode(minIndent: Int) -> Block {
        var content = ""
        var pendingBlanks: [String] = []
        while let line = peek() {
            if line.isBlank {
                pendingBlanks.append("")
                cursor += 1
                continue
            }
            guard line.indent - minIndent >= 4 else { break }
            // Flush buffered blank lines (they belong to the code block).
            for _ in pendingBlanks { content += "\n" }
            pendingBlanks.removeAll()
            let stripped = dropColumns(line, count: minIndent + 4)
            content += stripped
            content += "\n"
            cursor += 1
        }
        return .codeBlock(CodeBlock(language: nil, content: content, isClosed: true))
    }

    // MARK: Math block

    private mutating func parseMathBlock(open: MathFenceInfo, minIndent: Int) -> Block {
        cursor += 1
        var latexLines: [String] = []
        var isClosed = false

        // Single-line form: "$$ E=mc^2 $$" closes on the same line.
        if open.style == .dollar, let inline = open.inlineClosedBody {
            return .mathBlock(MathBlock(latex: inline, isClosed: true))
        }
        if open.style == .bracket, let inline = open.inlineClosedBody {
            return .mathBlock(MathBlock(latex: inline, isClosed: true))
        }

        // Any text after the opening delimiter on the opening line is content.
        if let leading = open.trailingContent, !leading.isEmpty {
            latexLines.append(leading)
        }

        while let line = peek() {
            let stripped = Substring(stripIndent(line, upTo: minIndent))
            if open.style == .dollar, stripped.trimmingChars(in: [" ", "\t"]) == "$$" {
                cursor += 1
                isClosed = true
                break
            }
            if open.style == .bracket, stripped.trimmingChars(in: [" ", "\t"]) == "\\]" {
                cursor += 1
                isClosed = true
                break
            }
            latexLines.append(String(stripped))
            cursor += 1
        }
        return .mathBlock(MathBlock(latex: latexLines.joined(separator: "\n"), isClosed: isClosed))
    }

    // MARK: Block quote

    private mutating func parseBlockQuote(minIndent: Int) -> Block {
        var innerLines: [RawLine] = []
        while let line = peek(), line.trimmed.hasPrefix(">"), line.indent - minIndent < 4 {
            var rest = line.trimmed.dropFirst() // drop '>'
            if rest.first == " " { rest = rest.dropFirst() }
            innerLines.append(RawLine(text: String(rest)))
            cursor += 1
        }
        // GitHub alert: a block quote whose first line is a bare `[!KIND]` marker
        // becomes a styled callout. The remaining lines are its body. An ordinary
        // quote that merely mentions `[!NOTE]` inline is not misclassified because
        // the marker must be the whole first line.
        if let first = innerLines.first, let kind = AlertKind.marker(in: first.trimmed) {
            var inner = BlockParser(lines: Array(innerLines.dropFirst()), depth: depth + 1)
            return .alert(Alert(kind: kind, blocks: inner.parseBlocks(minIndent: 0)))
        }
        var inner = BlockParser(lines: innerLines, depth: depth + 1)
        return .blockQuote(BlockQuote(blocks: inner.parseBlocks(minIndent: 0)))
    }

    // MARK: Footnote definitions

    /// Parses a GFM footnote definition (`[^id]: body`). The body is the text on
    /// the marker line plus any *contiguous* indented (≥ 4 column) continuation
    /// lines; a blank line ends the definition. Continuations stop at the first
    /// blank or dedented line so the definition's close coincides exactly with the
    /// commit boundary's blank-line rule, preserving streaming equivalence.
    private mutating func parseFootnoteDefinition(marker: FootnoteDefMarker, minIndent: Int) -> Block {
        var bodyLines: [RawLine] = [RawLine(text: String(marker.body))]
        cursor += 1
        while let next = peek(), !next.isBlank, next.indent - minIndent >= 4 {
            bodyLines.append(RawLine(text: dropColumns(next, count: minIndent + 4)))
            cursor += 1
        }
        var inner = BlockParser(lines: bodyLines, depth: depth + 1)
        let blocks = inner.parseBlocks(minIndent: 0)
        return .footnoteDefinition(FootnoteDefinition(marker: marker.id, blocks: blocks))
    }

    // MARK: Lists

    private mutating func parseList(firstMarker: ListMarker, minIndent: Int) -> Block {
        let isOrdered = firstMarker.isOrdered
        let start = firstMarker.ordinal ?? 1
        var items: [ListItem] = []
        var isTight = true
        var sawBlankBetweenItems = false

        while let line = peek() {
            if line.isBlank {
                // Could be a loose separator; peek ahead.
                let savedCursor = cursor
                cursor += 1
                // Skip following blanks.
                while let l = peek(), l.isBlank { cursor += 1 }
                if let next = peek(),
                   let marker = ListMarker(next.trimmed),
                   marker.isOrdered == isOrdered,
                   next.indent - minIndent < 4 {
                    sawBlankBetweenItems = true
                    continue
                } else {
                    cursor = savedCursor
                    break
                }
            }
            guard line.indent - minIndent < 4,
                  let marker = ListMarker(line.trimmed),
                  marker.isOrdered == isOrdered else {
                break
            }
            let item = parseListItem(marker: marker, baseIndent: minIndent)
            items.append(item)
        }
        if sawBlankBetweenItems { isTight = false }
        return .list(List(items: items, isOrdered: isOrdered, start: start, isTight: isTight))
    }

    private mutating func parseListItem(marker: ListMarker, baseIndent: Int) -> ListItem {
        // The content indentation is the marker's own indent plus its width.
        let line = lines[cursor]
        let contentIndent = line.indent + marker.width
        var itemLines: [RawLine] = []

        // First line: content after the marker (and optional task checkbox).
        var checkbox: Bool? = nil
        var firstContent = marker.rest
        if let box = TaskCheckbox(firstContent) {
            checkbox = box.checked
            firstContent = box.rest
        }
        itemLines.append(RawLine(text: String(firstContent)))
        cursor += 1

        // Continuation lines: lines indented to contentIndent, plus blank lines
        // that are themselves followed by such indented continuation. A blank
        // line followed by a sibling item (or end of list) is left for the
        // list-level loose-spacing scan, so it is not consumed here.
        while let next = peek() {
            if next.isBlank {
                // Look ahead past the run of blanks for a continuation line.
                var look = cursor + 1
                while look < lines.count, lines[look].isBlank { look += 1 }
                if look < lines.count, lines[look].indent >= contentIndent {
                    itemLines.append(RawLine(text: ""))
                    cursor += 1
                    continue
                }
                break
            }
            if next.indent >= contentIndent {
                itemLines.append(RawLine(text: dropColumns(next, count: contentIndent)))
                cursor += 1
                continue
            }
            break
        }
        // Trim trailing blank lines captured for this item.
        while itemLines.last?.isBlank == true { itemLines.removeLast() }

        var inner = BlockParser(lines: itemLines, depth: depth + 1)
        let blocks = inner.parseBlocks(minIndent: 0)
        return ListItem(blocks: blocks, checkbox: checkbox)
    }

    // MARK: HTML block

    private func isHTMLBlockStart(_ content: Substring) -> Bool {
        guard content.first == "<" else { return false }
        let after = content.dropFirst()
        guard let c = after.first else { return false }
        return c.isLetter || c == "/" || c == "!" || c == "?"
    }

    private mutating func parseHTMLBlock(minIndent: Int) -> Block {
        var htmlLines: [String] = []
        while let line = peek(), !line.isBlank {
            htmlLines.append(line.text)
            cursor += 1
        }
        return .htmlBlock(HTMLBlock(raw: htmlLines.joined(separator: "\n")))
    }

    // MARK: Tables

    private func isTableHeader(at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmed
        let delim = lines[index + 1].trimmed
        guard header.contains("|") else { return false }
        return isDelimiterRow(delim)
    }

    private func isDelimiterRow(_ line: Substring) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        for cell in cells {
            let t = cell.trimmingChars(in: [" ", "\t"])
            guard !t.isEmpty else { return false }
            var body = Substring(t)
            if body.first == ":" { body = body.dropFirst() }
            if body.last == ":" { body = body.dropLast() }
            guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return false }
        }
        return true
    }

    private mutating func parseTable(minIndent: Int) -> Block {
        let headerCells = splitTableRow(lines[cursor].trimmed).map {
            deferredInlines($0.trimmingChars(in: [" ", "\t"]))
        }
        cursor += 1
        let alignments = parseAlignments(lines[cursor].trimmed)
        cursor += 1

        var rows: [[[Inline]]] = []
        while let line = peek(), !line.isBlank, line.trimmed.contains("|") {
            let cells = splitTableRow(line.trimmed).map {
                deferredInlines($0.trimmingChars(in: [" ", "\t"]))
            }
            rows.append(cells)
            cursor += 1
        }
        return .table(Table(header: headerCells, rows: rows, alignments: alignments))
    }

    private func parseAlignments(_ line: Substring) -> [ColumnAlignment] {
        splitTableRow(line).map { cell in
            let t = cell.trimmingChars(in: [" ", "\t"])
            let left = t.hasPrefix(":")
            let right = t.hasSuffix(":")
            switch (left, right) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            case (false, false): return .none
            }
        }
    }

    private func splitTableRow(_ line: Substring) -> [String] {
        var s = line
        if s.first == "|" { s = s.dropFirst() }
        if s.last == "|" { s = s.dropLast() }
        // Split on unescaped pipes.
        var cells: [String] = []
        var current = ""
        var escaped = false
        for c in s {
            if escaped {
                current.append(c)
                escaped = false
            } else if c == "\\" {
                current.append(c)
                escaped = true
            } else if c == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        cells.append(current)
        return cells
    }

    // MARK: Indent helpers

    /// Removes up to `count` columns of leading whitespace from a line's text.
    private func dropColumns(_ line: RawLine, count: Int) -> String {
        var col = 0
        var idx = line.text.startIndex
        while idx < line.text.endIndex, col < count {
            let c = line.text[idx]
            if c == " " { col += 1 }
            else if c == "\t" { col += 4 - (col % 4) }
            else { break }
            idx = line.text.index(after: idx)
        }
        return String(line.text[idx...])
    }

    /// Strips up to `upTo` columns of indentation but preserves the rest of the
    /// line's leading whitespace (used inside fenced code, where interior indent
    /// is significant).
    private func stripIndent(_ line: RawLine, upTo: Int) -> String {
        dropColumns(line, count: upTo)
    }
}

// MARK: - Deferred inline span

/// Wraps verbatim block text as a single deferred ``Inline/text`` span.
///
/// Empty text yields an empty inline array. A later inline-parsing pass replaces
/// these spans with fully parsed inline trees.
func deferredInlines(_ text: String) -> [Inline] {
    text.isEmpty ? [] : [.text(text)]
}

// MARK: - Construct recognizers

/// A recognized code-fence opener (` ``` ` or `~~~`).
private struct FenceInfo {
    let char: Character
    let length: Int
    let info: Substring

    init?(_ content: Substring) {
        guard let first = content.first, first == "`" || first == "~" else { return nil }
        var count = 0
        var idx = content.startIndex
        while idx < content.endIndex, content[idx] == first {
            count += 1
            idx = content.index(after: idx)
        }
        guard count >= 3 else { return nil }
        let rest = content[idx...].trimmingChars(in: [" ", "\t"])
        // A backtick info string may not itself contain a backtick.
        if first == "`", rest.contains("`") { return nil }
        self.char = first
        self.length = count
        self.info = Substring(rest)
    }
}

/// The delimiter family of a display-math block.
private enum MathStyle { case dollar, bracket }

/// A recognized display-math opener (`$$` or `\[`).
private struct MathFenceInfo {
    let style: MathStyle
    /// Content following the delimiter on the opening line, if any.
    let trailingContent: String?
    /// For a single-line `$$ … $$` / `\[ … \]`, the enclosed body.
    let inlineClosedBody: String?

    init?(_ content: Substring) {
        if content.hasPrefix("$$") {
            self.style = .dollar
            let after = content.dropFirst(2)
            let trimmed = after.trimmingChars(in: [" ", "\t"])
            if trimmed.hasSuffix("$$"), trimmed.count >= 2 {
                let body = trimmed.dropLast(2).trimmingChars(in: [" ", "\t"])
                self.inlineClosedBody = String(body)
                self.trailingContent = nil
            } else {
                self.inlineClosedBody = nil
                self.trailingContent = trimmed.isEmpty ? nil : String(trimmed)
            }
            return
        }
        if content.hasPrefix("\\[") {
            self.style = .bracket
            let after = content.dropFirst(2)
            let trimmed = after.trimmingChars(in: [" ", "\t"])
            if trimmed.hasSuffix("\\]"), trimmed.count >= 2 {
                let body = trimmed.dropLast(2).trimmingChars(in: [" ", "\t"])
                self.inlineClosedBody = String(body)
                self.trailingContent = nil
            } else {
                self.inlineClosedBody = nil
                self.trailingContent = trimmed.isEmpty ? nil : String(trimmed)
            }
            return
        }
        return nil
    }
}

/// A recognized list-item marker (bullet `-`/`*`/`+` or ordered `N.`/`N)`).
private struct ListMarker {
    let isOrdered: Bool
    let ordinal: Int?
    /// Total marker width in columns (marker glyph(s) + following space).
    let width: Int
    /// The item content following the marker.
    let rest: Substring

    init?(_ content: Substring) {
        guard let first = content.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let after = content.dropFirst()
            guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
            var rest = after
            if rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
            self.isOrdered = false
            self.ordinal = nil
            self.width = 2
            self.rest = rest
            return
        }
        if first.isNumber {
            var idx = content.startIndex
            var digits = ""
            while idx < content.endIndex, content[idx].isNumber {
                digits.append(content[idx])
                idx = content.index(after: idx)
            }
            guard idx < content.endIndex else { return nil }
            let punct = content[idx]
            guard punct == "." || punct == ")" else { return nil }
            let afterPunct = content.index(after: idx)
            var rest = content[afterPunct...]
            guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
            if rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
            self.isOrdered = true
            self.ordinal = Int(digits)
            self.width = digits.count + 2 // digits + punctuation + space
            self.rest = rest
            return
        }
        return nil
    }
}

/// A recognized GFM footnote-definition opener (`[^id]:`).
private struct FootnoteDefMarker {
    /// The footnote label, without the `[^` and `]`.
    let id: String
    /// The definition body text following the `]:` on the opening line.
    let body: Substring

    init?(_ content: Substring) {
        guard content.hasPrefix("[^") else { return nil }
        var rest = content.dropFirst(2)
        var id = ""
        while let c = rest.first, c != "]" {
            // Labels may not contain whitespace or a nested bracket.
            guard c != " ", c != "\t", c != "[" else { return nil }
            id.append(c)
            rest = rest.dropFirst()
        }
        guard rest.first == "]", !id.isEmpty else { return nil }
        rest = rest.dropFirst() // drop ']'
        guard rest.first == ":" else { return nil }
        rest = rest.dropFirst() // drop ':'
        if rest.first == " " { rest = rest.dropFirst() }
        self.id = id
        self.body = rest
    }
}

/// A GFM task-list checkbox at the start of a list item's content.
private struct TaskCheckbox {
    let checked: Bool
    let rest: Substring

    init?(_ content: Substring) {
        guard content.hasPrefix("[") else { return nil }
        let after = content.dropFirst()
        guard let mark = after.first else { return nil }
        let isChecked: Bool
        switch mark {
        case " ": isChecked = false
        case "x", "X": isChecked = true
        default: return nil
        }
        let afterMark = after.dropFirst()
        guard afterMark.first == "]" else { return nil }
        var rest = afterMark.dropFirst()
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        if rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
        self.checked = isChecked
        self.rest = rest
    }
}

// MARK: - Substring trimming helper

private extension Substring {
    /// Trims the given characters from both ends.
    func trimmingChars(in set: Set<Character>) -> Substring {
        var s = self
        while let f = s.first, set.contains(f) { s = s.dropFirst() }
        while let l = s.last, set.contains(l) { s = s.dropLast() }
        return s
    }
}

private extension String {
    func trimmingChars(in set: Set<Character>) -> String {
        String(Substring(self).trimmingChars(in: set))
    }
}
