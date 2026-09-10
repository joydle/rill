/// A single physical line produced by ``LineScanner``.
///
/// `Line` carries the line's UTF-8 ``bytes`` (excluding the terminating
/// newline), the absolute source ``range`` of those bytes within the original
/// buffer, and whether the line was ``terminatedByNewline``. The absolute range
/// lets the block lexer and commit-boundary scan map blocks back to byte offsets
/// in the streaming buffer.
struct Line {
    /// The line's content bytes, excluding any terminating `\n`.
    let bytes: ArraySlice<UInt8>

    /// The absolute source byte range of ``bytes`` within the scanned buffer,
    /// using the buffer's own indices (the newline, if any, is not included).
    let range: Range<Int>

    /// Whether this line was terminated by a `\n` in the source (`false` for a
    /// final line with no trailing newline).
    let terminatedByNewline: Bool
}

/// A forward, allocation-light splitter that walks a UTF-8 byte slice line by
/// line.
///
/// `LineScanner` recognizes `\n` as the line terminator and strips a single
/// preceding `\r` so CRLF input behaves like LF. It preserves absolute byte
/// offsets so the block lexer can attribute source ranges, and it yields a final
/// unterminated line when the buffer does not end in a newline (the streaming
/// "open tail").
struct LineScanner {
    private let bytes: ArraySlice<UInt8>
    private var cursor: Int

    /// Creates a scanner over a UTF-8 byte slice. The slice's own indices are
    /// preserved in emitted ``Line/range`` values.
    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.cursor = bytes.startIndex
    }

    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    /// Returns the next line, or `nil` once the buffer is exhausted.
    mutating func next() -> Line? {
        let end = bytes.endIndex
        guard cursor < end else { return nil }

        let lineStart = cursor
        var i = cursor
        while i < end, bytes[i] != Self.newline {
            i += 1
        }

        if i < end {
            // Found a newline at i. Content is [lineStart, i), trimming a CR.
            var contentEnd = i
            if contentEnd > lineStart, bytes[contentEnd - 1] == Self.carriageReturn {
                contentEnd -= 1
            }
            cursor = i + 1
            return Line(
                bytes: bytes[lineStart..<contentEnd],
                range: lineStart..<contentEnd,
                terminatedByNewline: true
            )
        } else {
            // No trailing newline: final unterminated line.
            var contentEnd = end
            if contentEnd > lineStart, bytes[contentEnd - 1] == Self.carriageReturn {
                contentEnd -= 1
            }
            cursor = end
            return Line(
                bytes: bytes[lineStart..<contentEnd],
                range: lineStart..<contentEnd,
                terminatedByNewline: false
            )
        }
    }
}
