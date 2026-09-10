import XCTest
@testable import RillCore

/// The headline correctness contract: for any input string and *any* chunking,
/// feeding the chunks sequentially into ``IncrementalParser`` must yield a final
/// ``Document`` byte-identical to parsing the whole string in one shot.
///
/// Each corpus document is fed three ways — one byte at a time, in randomized
/// chunks, and split on word boundaries — and the resulting document is compared
/// against the one-shot lexer-plus-inline reference. The corpus spans headings,
/// nested lists, tables, fenced code, math, and mixed documents.
final class IncrementalEquivalenceTests: XCTestCase {

    /// The one-shot reference parse: block-lex the whole buffer, then resolve
    /// every deferred inline span. This is what the incremental engine must match.
    private func oneShot(_ source: String, config: ParseConfig = .default) -> Document {
        let bytes = Array(source.utf8)
        let blocks = BlockLexer.lex(bytes[...])
        let resolved = InlineParser.resolveInlines(in: blocks, config: config)
        return Document(blocks: resolved)
    }

    /// Splits a string's UTF-8 into chunks at the given byte offsets, never
    /// splitting a multi-byte scalar. Returns the chunk strings in order.
    private func utf8Chunks(_ source: String, boundaries rawBoundaries: [Int]) -> [String] {
        let bytes = Array(source.utf8)
        guard !bytes.isEmpty else { return [] }
        // Compute the set of legal scalar boundaries.
        var legal = Set<Int>([0, bytes.count])
        var idx = 0
        for scalar in source.unicodeScalars {
            idx += String(scalar).utf8.count
            legal.insert(idx)
        }
        var cuts = rawBoundaries
            .map { max(0, min(bytes.count, $0)) }
            .filter { legal.contains($0) }
        cuts.append(0)
        cuts.append(bytes.count)
        let ordered = Array(Set(cuts)).sorted()
        var chunks: [String] = []
        for i in 1..<ordered.count {
            let slice = bytes[ordered[i - 1]..<ordered[i]]
            if slice.isEmpty { continue }
            chunks.append(String(decoding: slice, as: UTF8.self))
        }
        return chunks
    }

    /// Feeds `chunks` as append-deltas into a fresh parser and returns the final
    /// document.
    private func feedDeltas(_ chunks: [String]) -> Document {
        let parser = IncrementalParser()
        var offset = 0
        for chunk in chunks {
            parser.consume(delta: chunk, at: offset)
            offset += chunk.utf8.count
        }
        return parser.document
    }

    /// Feeds growing snapshots into a fresh parser and returns the final document.
    private func feedSnapshots(_ chunks: [String]) -> Document {
        let parser = IncrementalParser()
        var accumulated = ""
        for chunk in chunks {
            accumulated += chunk
            parser.consume(snapshot: accumulated)
        }
        return parser.document
    }

    // MARK: Corpus

    /// ~30 representative documents covering the practical CommonMark + GFM
    /// subset Rill targets.
    private static let corpus: [String] = [
        "# Hello\n",
        "# Heading\n\nA paragraph of text.\n",
        "## Level two\n### Level three\n#### Level four\n",
        "Just a single paragraph with no trailing newline.",
        "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n",
        "A paragraph\nthat wraps across\nseveral lines.\n",
        "- one\n- two\n- three\n",
        "1. first\n2. second\n3. third\n",
        "- a\n  - a1\n  - a2\n- b\n  - b1\n",
        "- loose\n\n- list\n\n- items\n",
        "- [ ] todo\n- [x] done\n- [ ] later\n",
        "1. ordered\n   - nested bullet\n   - another\n2. second\n",
        "> a quote\n> spanning lines\n",
        "> outer\n> > nested\n> back to outer\n",
        "```swift\nlet x = 1\nprint(x)\n```\n",
        "~~~\nplain fenced\n~~~\n",
        "```\nno language\nmore code\n```\n",
        "Some text then code:\n\n```python\ndef f():\n    return 1\n```\n\nAfter.\n",
        "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n",
        "| left | center | right |\n|:---|:---:|---:|\n| l | c | r |\n",
        "$$\nE = mc^2\n$$\n",
        "$$ a + b = c $$\n",
        "\\[\n\\frac{1}{2}\n\\]\n",
        "Inline math $x^2$ and \\(y_i\\) here.\n",
        "Text with *emphasis*, **strong**, and ~~strike~~.\n",
        "A [link](https://example.com \"title\") and `code span`.\n",
        "Bare url https://swift.org and autolink <https://apple.com>.\n",
        "Citation [1] and footnote [^note] in a line.\n",
        "***\n\nAbove and below a thematic break.\n\n***\n",
        "# Title\n\nIntro paragraph.\n\n- bullet one\n- bullet two\n\n```swift\nlet y = 2\n```\n\n| h1 | h2 |\n|---|---|\n| a | b |\n\n> quoted finish\n",
        "Mixed: a paragraph with $a+b$ math, a [2] citation, **bold**, then:\n\n1. step one\n2. step two\n\n$$\n\\sum_{i=0}^n i\n$$\n\nDone.\n",
        "Heading then immediate list\n# H\n- item\n",
        // Indented (4-column) code blocks — including an internal blank line,
        // which is interior content and must never be a commit boundary.
        "    indented code\n    line two\n",
        "    a\n\n    b\n",
        "Paragraph before.\n\n    code block\n    second line\n\nAfter the code.\n",
        "- outer item\n\n      code in item\n      second line\n\n- second item\n",
        // CRLF input must normalize to LF-equivalent block structure.
        "# H\r\n\r\npara\r\n",
        "First line\r\nsecond line\r\n\r\n- a\r\n- b\r\n",
        // GitHub alerts: each kind, plus a multi-line body and a plain quote that
        // must stay a quote.
        "> [!NOTE]\n> A note callout.\n",
        "> [!WARNING]\n> Be careful here.\n> Second line.\n",
        "> [!TIP]\n> Try this:\n>\n> - one\n> - two\n",
        "> a plain quote\n> not an alert\n",
        "Intro.\n\n> [!IMPORTANT]\n> Important detail.\n\nOutro.\n",
        // Footnotes: a reference and its definition, and a definition with an
        // indented continuation line.
        "A claim with a footnote[^1].\n\n[^1]: The supporting detail.\n",
        "Text[^note] here.\n\n[^note]: First line of the note.\n    Continued line.\n",
        "Two refs[^a] and[^b].\n\n[^a]: First.\n\n[^b]: Second.\n",
    ]

    // MARK: Tests

    func testOneByteChunkingEquivalence() {
        for (i, doc) in Self.corpus.enumerated() {
            let chunks = utf8Chunks(doc, boundaries: Array(0...doc.utf8.count))
            let expected = oneShot(doc)
            let viaDelta = feedDeltas(chunks)
            XCTAssertEqual(viaDelta, expected, "1-byte delta mismatch for corpus[\(i)]")
            let viaSnapshot = feedSnapshots(chunks)
            XCTAssertEqual(viaSnapshot, expected, "1-byte snapshot mismatch for corpus[\(i)]")
        }
    }

    func testRandomChunkingEquivalence() {
        var rng = SeededRNG(seed: seedConstant())
        for (i, doc) in Self.corpus.enumerated() {
            let expected = oneShot(doc)
            for trial in 0..<5 {
                var boundaries: [Int] = []
                var cursor = 0
                while cursor < doc.utf8.count {
                    let step = Int(rng.next() % 7) + 1
                    cursor += step
                    boundaries.append(min(cursor, doc.utf8.count))
                }
                let chunks = utf8Chunks(doc, boundaries: boundaries)
                let viaDelta = feedDeltas(chunks)
                XCTAssertEqual(viaDelta, expected, "random delta mismatch corpus[\(i)] trial \(trial)")
            }
        }
    }

    func testWordBoundaryChunkingEquivalence() {
        for (i, doc) in Self.corpus.enumerated() {
            let expected = oneShot(doc)
            // Word boundaries: cut after every run of whitespace.
            var boundaries: [Int] = []
            var offset = 0
            var prevWasSpace = false
            for scalar in doc.unicodeScalars {
                offset += String(scalar).utf8.count
                let isSpace = scalar == " " || scalar == "\n" || scalar == "\t"
                if prevWasSpace && !isSpace {
                    boundaries.append(offset - String(scalar).utf8.count)
                }
                prevWasSpace = isSpace
            }
            let chunks = utf8Chunks(doc, boundaries: boundaries)
            let viaDelta = feedDeltas(chunks)
            XCTAssertEqual(viaDelta, expected, "word-boundary delta mismatch corpus[\(i)]")
            let viaSnapshot = feedSnapshots(chunks)
            XCTAssertEqual(viaSnapshot, expected, "word-boundary snapshot mismatch corpus[\(i)]")
        }
    }

    /// An idempotent re-send of a delta at an earlier offset must not corrupt
    /// the buffer: re-sending the same suffix yields the same document as
    /// sending it once.
    func testIdempotentReEmit() {
        let doc = "# Title\n\nBody paragraph.\n\n- a\n- b\n"
        let expected = oneShot(doc)
        let parser = IncrementalParser()
        let bytes = Array(doc.utf8)
        // Send first 10 bytes, then re-send from byte 5 (overlapping), then rest.
        parser.consume(delta: String(decoding: bytes[0..<10], as: UTF8.self), at: 0)
        parser.consume(delta: String(decoding: bytes[5..<bytes.count], as: UTF8.self), at: 5)
        // Re-emit the whole thing again from 0 (snapshot-like idempotency).
        parser.consume(delta: doc, at: 0)
        XCTAssertEqual(parser.document, expected)
    }
}

/// A tiny deterministic xorshift RNG so chunking trials are reproducible.
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef : seed }
    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }
}

/// A fixed nonzero seed constant for the random-chunking trials.
private func seedConstant() -> UInt64 { 0x9E37_79B9_7F4A_7C15 }
