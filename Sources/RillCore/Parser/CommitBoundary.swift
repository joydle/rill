/// Computes the streaming commit boundary: the byte offset past the last
/// definitively-closed block.
///
/// All bytes before ``lastClosedIndex(in:)`` belong to blocks that can never
/// change as more text arrives, so the incremental engine may freeze them and
/// re-lex only the dirty tail. A position is a safe boundary only at block level
/// (not inside an open construct) and only when the preceding block is closed:
///
/// - paragraph closed by a blank line,
/// - fenced code closed by its closing fence,
/// - math block closed by `$$` / `\]`,
/// - ATX heading / thematic break (single-line, closes at its newline).
///
/// Constructs that *block* committing keep the tail open: an unterminated fence
/// or math block, and the final paragraph/list/table (which a future line could
/// extend via lazy continuation or a new row). Conservatively, this scanner only
/// commits the prefix up to the last blank line that follows fully-closed
/// content, plus any leading run of single-line atoms (headings, thematic
/// breaks, closed fences/math) that are immediately followed by a newline.
public enum CommitBoundary {
    /// Returns the byte offset just past the last definitively-closed block in
    /// the buffer.
    ///
    /// - Parameter buffer: The full UTF-8 buffer (or dirty-tail slice).
    /// - Returns: A byte offset, expressed in the buffer slice's own index space,
    ///   such that every byte before it belongs to a closed block. Returns the
    ///   slice's `startIndex` when nothing can be committed yet.
    public static func lastClosedIndex(in buffer: ArraySlice<UInt8>) -> Int {
        let start = buffer.startIndex
        let end = buffer.endIndex
        guard start < end else { return start }

        var scanner = LineScanner(buffer)
        var committed = start

        // Track the offset that follows each line (including its newline).
        var lineEnds: [(range: Range<Int>, terminated: Bool, raw: RawLine)] = []
        while let line = scanner.next() {
            let raw = RawLine(text: String(decoding: line.bytes, as: UTF8.self))
            lineEnds.append((line.range, line.terminatedByNewline, raw))
        }

        var i = 0
        // Offset past the most recent fully-closed boundary candidate.
        while i < lineEnds.count {
            let entry = lineEnds[i]
            let content = entry.raw.trimmed

            // Open code fence: scan to a matching closing fence.
            if entry.raw.indent < 4, isFenceOpen(content) {
                if let closeEnd = fenceCloseOffset(lineEnds, from: i) {
                    committed = closeEnd
                    i = advance(lineEnds, past: closeEnd)
                    continue
                } else {
                    // Unterminated fence: nothing from here on commits.
                    break
                }
            }

            // Open math block ($$ / \[): scan to its close.
            if entry.raw.indent < 4, let style = mathOpen(content) {
                if let closeEnd = mathCloseOffset(lineEnds, from: i, style: style) {
                    committed = closeEnd
                    i = advance(lineEnds, past: closeEnd)
                    continue
                } else {
                    break
                }
            }

            // Single-line atoms: heading / thematic break. Commit through their
            // newline (they cannot be extended).
            if entry.raw.indent < 4, isSingleLineAtom(content), entry.terminated {
                committed = entry.range.upperBound + 1 // include the newline
                i += 1
                continue
            }

            // Blank line: marks a closed boundary. Commit through its newline —
            // unless the next non-blank line begins a list-item marker, in which
            // case this blank may be a *loose-list* separator binding two sibling
            // items into one list. Committing there would split the list and
            // break streaming equivalence, so stop instead.
            if entry.raw.isBlank, entry.terminated {
                if nextNonBlankStartsList(lineEnds, after: i) { break }
                committed = entry.range.upperBound + 1
                i += 1
                continue
            }

            // A list: scan the whole list (across loose blank separators) to its
            // definitive close. A list closes only at a blank line that is NOT
            // followed by a sibling marker — i.e. followed by genuinely different,
            // non-indented content. A trailing list (no such closer before end of
            // input) stays open, exactly like a trailing paragraph.
            if entry.raw.indent < 4, startsListMarker(content) {
                if let closeEnd = listCloseOffset(lineEnds, from: i) {
                    committed = closeEnd.offset
                    i = closeEnd.nextIndex
                    continue
                }
                break
            }

            // An indented code block (>=4 columns at block level). Its interior
            // blank lines are buffered by ``BlockLexer/parseIndentedCode`` and so
            // belong to the block — an internal blank must never be used as a
            // commit boundary (which would split the block and break streaming
            // equivalence). Scan it like a fenced/math region: skip interior
            // blanks and commit only once the region definitively closes at a
            // dedent to non-blank content.
            if entry.raw.indent >= 4 {
                if let closeEnd = indentedCodeCloseOffset(lineEnds, from: i) {
                    committed = closeEnd.offset
                    i = closeEnd.nextIndex
                    continue
                }
                break
            }

            // Otherwise this is paragraph/list/table body. It commits only once
            // a blank line definitively closes it (a future line could otherwise
            // extend it via lazy continuation or a new row). Scan forward for the
            // closing blank line; commit through it if found, else stop.
            if let blankEnd = nextBlankClose(lineEnds, from: i) {
                committed = blankEnd.offset
                i = blankEnd.nextIndex
                continue
            }
            break
        }

        return committed
    }

    /// Scans forward from a paragraph/list/table body line for the blank line
    /// that closes it, skipping over any fenced-code or math regions that begin
    /// within the body (e.g. a fence inside a list item). Returns the offset just
    /// past the closing blank line and the index to resume from, or `nil` if no
    /// terminated blank line closes the body before end of input.
    private static func nextBlankClose(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        from index: Int
    ) -> (offset: Int, nextIndex: Int)? {
        var j = index
        while j < lines.count {
            let content = lines[j].raw.trimmed
            if lines[j].raw.indent < 4, isFenceOpen(content) {
                if let closeEnd = fenceCloseOffset(lines, from: j) {
                    j = advance(lines, past: closeEnd)
                    continue
                } else {
                    return nil // unterminated fence: nothing commits
                }
            }
            if lines[j].raw.indent < 4, let style = mathOpen(content) {
                if let closeEnd = mathCloseOffset(lines, from: j, style: style) {
                    j = advance(lines, past: closeEnd)
                    continue
                } else {
                    return nil
                }
            }
            // A list marker within the scanned body means this region is (or
            // contains) a list, whose own conservative closing rules govern when
            // it may commit. A blank after it could be a loose-list separator that
            // a later sibling extends, so do not commit through it from the
            // paragraph path — keep the region open and let the list be re-lexed
            // in the live tail (streaming equivalence).
            if lines[j].raw.indent < 4, startsListMarker(content) {
                return nil
            }
            if lines[j].raw.isBlank, lines[j].terminated {
                // A blank that is immediately followed by a list-item marker may
                // be a loose-list separator; it does not close the body. Treat
                // the body as still open so the list stays in the live tail.
                if nextNonBlankStartsList(lines, after: j) { return nil }
                return (lines[j].range.upperBound + 1, j + 1)
            }
            j += 1
        }
        return nil
    }

    /// Scans a list beginning at `openIndex` to its definitive close and returns
    /// the offset just past the closing blank line plus the resume index, or `nil`
    /// if the list is still open (the trailing block).
    ///
    /// A list spans its item markers, their indented continuation lines, and the
    /// loose blank lines that separate sibling items. It closes only at a blank
    /// line whose following non-blank line is a *different* construct — a
    /// non-indented, non-list line — that cannot be a list continuation. A fence
    /// or math block opened inside an item is skipped over so a blank inside code
    /// is not mistaken for a list close.
    private static func listCloseOffset(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        from openIndex: Int
    ) -> (offset: Int, nextIndex: Int)? {
        var j = openIndex
        while j < lines.count {
            let line = lines[j]
            let content = line.raw.trimmed

            // Skip fenced code / math opened within a list item.
            if line.raw.indent < 4, isFenceOpen(content) {
                if let closeEnd = fenceCloseOffset(lines, from: j) {
                    j = advance(lines, past: closeEnd)
                    continue
                }
                return nil
            }
            if line.raw.indent < 4, let style = mathOpen(content) {
                if let closeEnd = mathCloseOffset(lines, from: j, style: style) {
                    j = advance(lines, past: closeEnd)
                    continue
                }
                return nil
            }

            if line.raw.isBlank {
                guard line.terminated else { return nil }
                // Find the next non-blank line.
                var k = j + 1
                while k < lines.count, lines[k].raw.isBlank { k += 1 }
                guard k < lines.count else {
                    // Trailing blank(s) with nothing after: list still open.
                    return nil
                }
                let nextLine = lines[k]
                // The list closes ONLY at a TERMINATED, column-0, non-list-marker
                // line — content that can never become a loose sibling item or an
                // indented continuation of this list. An indented line, a sibling
                // marker, or an unterminated/partial line (whose classification
                // could still change as bytes arrive) all keep the list open so it
                // is re-lexed in the live tail, preserving streaming equivalence.
                let closes = nextLine.terminated
                    && nextLine.raw.indent == 0
                    && !startsListMarker(nextLine.raw.trimmed)
                if closes {
                    return (line.range.upperBound + 1, j + 1)
                }
                // Otherwise keep scanning; the list stays open through this blank.
                j = k
                continue
            }

            j += 1
        }
        return nil
    }

    /// Scans an indented code block beginning at `openIndex` (a non-blank line
    /// with indent >= 4 at block level) to its definitive close, mirroring
    /// ``BlockLexer/parseIndentedCode``.
    ///
    /// The region spans consecutive indented (>= 4 column) lines plus any blank
    /// lines that are themselves followed by further indented content (interior
    /// blanks belong to the code). It closes only at a dedent to non-blank
    /// content with indent < 4 — committing through that closing blank line, or
    /// through the last code line when the dedent is immediate. A region that
    /// reaches end of input stays open (the trailing block), since a future line
    /// could extend it.
    private static func indentedCodeCloseOffset(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        from openIndex: Int
    ) -> (offset: Int, nextIndex: Int)? {
        var j = openIndex
        while j < lines.count {
            let line = lines[j]
            if line.raw.isBlank {
                guard line.terminated else { return nil }
                // Look past the run of blanks for the next non-blank line.
                var k = j + 1
                while k < lines.count, lines[k].raw.isBlank { k += 1 }
                guard k < lines.count else {
                    // Trailing blank(s): more indented lines could still arrive,
                    // so the block stays open in the live tail.
                    return nil
                }
                if lines[k].raw.indent >= 4 {
                    // Interior blank inside the code region: code continues.
                    j = k
                    continue
                }
                // Blank followed by a dedented line: the code closes here,
                // through this blank line.
                return (line.range.upperBound + 1, j + 1)
            }
            if line.raw.indent >= 4 {
                j += 1
                continue
            }
            // A non-blank dedented line with no preceding blank: the code closes
            // immediately before it; commit through the previous code line.
            return (lines[j - 1].range.upperBound + 1, j)
        }
        // Reached end of input still inside the code region: trailing/open block.
        return nil
    }

    /// Whether the first non-blank line after `index` begins a list-item marker
    /// (`-`/`*`/`+` bullet or `N.`/`N)` ordinal). Used to detect a loose-list
    /// blank separator that must not be committed across.
    private static func nextNonBlankStartsList(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        after index: Int
    ) -> Bool {
        var k = index + 1
        while k < lines.count, lines[k].raw.isBlank { k += 1 }
        guard k < lines.count else { return false }
        let line = lines[k]
        guard line.raw.indent < 4 else { return false }
        return startsListMarker(line.raw.trimmed)
    }

    /// Recognizes a list-item marker at the start of a line's trimmed content,
    /// mirroring ``BlockLexer``'s marker grammar.
    private static func startsListMarker(_ content: Substring) -> Bool {
        guard let first = content.first else { return false }
        if first == "-" || first == "*" || first == "+" {
            let after = content.dropFirst()
            return after.isEmpty || after.first == " " || after.first == "\t"
        }
        if first.isNumber {
            var idx = content.startIndex
            while idx < content.endIndex, content[idx].isNumber {
                idx = content.index(after: idx)
            }
            guard idx < content.endIndex else { return false }
            let punct = content[idx]
            guard punct == "." || punct == ")" else { return false }
            let after = content.index(after: idx)
            return after == content.endIndex || content[after] == " " || content[after] == "\t"
        }
        return false
    }

    // MARK: Recognizers (block-level, mirroring BlockLexer)

    private static func isFenceOpen(_ content: Substring) -> Bool {
        guard let first = content.first, first == "`" || first == "~" else { return false }
        var count = 0
        for c in content {
            if c == first { count += 1 } else { break }
        }
        return count >= 3
    }

    private static func fenceChar(_ content: Substring) -> Character? {
        guard let first = content.first, first == "`" || first == "~" else { return nil }
        return first
    }

    private static func fenceLength(_ content: Substring, char: Character) -> Int {
        var count = 0
        for c in content { if c == char { count += 1 } else { break } }
        return count
    }

    private static func fenceCloseOffset(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        from openIndex: Int
    ) -> Int? {
        let openContent = lines[openIndex].raw.trimmed
        guard let oc = fenceChar(openContent) else { return nil }
        let openLen = fenceLength(openContent, char: oc)
        let openIndent = lines[openIndex].raw.indent
        var j = openIndex + 1
        while j < lines.count {
            let lc = lines[j].raw.trimmed
            // A closing fence must sit at the SAME indentation as the opener.
            // BlockLexer strips only the container indent before matching a
            // closer, so an extra-indented `  ``` ` is code content, not a close.
            // Enforcing the same rule here keeps the commit boundary consistent
            // with the one-shot lexer (streaming equivalence) — without it, an
            // indented closing fence committed here but stayed open one-shot.
            if lines[j].raw.indent == openIndent,
               let cc = fenceChar(lc), cc == oc, fenceLength(lc, char: oc) >= openLen {
                // Closing fence must have no trailing info.
                let after = lc.drop { $0 == oc }.trimmingChars(in: [" ", "\t"])
                if after.isEmpty, lines[j].terminated {
                    return lines[j].range.upperBound + 1
                }
            }
            j += 1
        }
        return nil
    }

    private static func mathOpen(_ content: Substring) -> MathDelim? {
        if content.hasPrefix("$$") {
            // Single-line "$$ … $$" closes immediately.
            let after = content.dropFirst(2).trimmingChars(in: [" ", "\t"])
            if after.hasSuffix("$$"), after.count >= 2 { return .singleLine }
            return .dollar
        }
        if content.hasPrefix("\\[") {
            let after = content.dropFirst(2).trimmingChars(in: [" ", "\t"])
            if after.hasSuffix("\\]"), after.count >= 2 { return .singleLine }
            return .bracket
        }
        return nil
    }

    private enum MathDelim { case dollar, bracket, singleLine }

    private static func mathCloseOffset(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        from openIndex: Int,
        style: MathDelim
    ) -> Int? {
        if style == .singleLine {
            let entry = lines[openIndex]
            return entry.terminated ? entry.range.upperBound + 1 : nil
        }
        let closer = style == .dollar ? "$$" : "\\]"
        var j = openIndex + 1
        while j < lines.count {
            let lc = lines[j].raw.trimmed.trimmingChars(in: [" ", "\t"])
            if lc == closer, lines[j].terminated {
                return lines[j].range.upperBound + 1
            }
            j += 1
        }
        return nil
    }

    private static func isSingleLineAtom(_ content: Substring) -> Bool {
        isATXHeading(content) || isThematicBreak(content)
    }

    private static func isATXHeading(_ content: Substring) -> Bool {
        var level = 0
        var idx = content.startIndex
        while idx < content.endIndex, content[idx] == "#" {
            level += 1
            idx = content.index(after: idx)
        }
        guard level >= 1, level <= 6 else { return false }
        if idx < content.endIndex {
            return content[idx] == " " || content[idx] == "\t"
        }
        return true
    }

    private static func isThematicBreak(_ content: Substring) -> Bool {
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

    /// Returns the index of the first line entry whose range starts at or after
    /// `offset`, used to resume scanning past a committed region.
    private static func advance(
        _ lines: [(range: Range<Int>, terminated: Bool, raw: RawLine)],
        past offset: Int
    ) -> Int {
        var k = 0
        while k < lines.count, lines[k].range.lowerBound < offset {
            k += 1
        }
        return k
    }
}

private extension Substring {
    func trimmingChars(in set: Set<Character>) -> Substring {
        var s = self
        while let f = s.first, set.contains(f) { s = s.dropFirst() }
        while let l = s.last, set.contains(l) { s = s.dropLast() }
        return s
    }
}
