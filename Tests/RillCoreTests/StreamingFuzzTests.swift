import XCTest
@testable import RillCore

/// Property-based fuzz coverage for the headline streaming-equivalence invariant:
/// for any document and ANY chunking, the incrementally-streamed `Document` must
/// equal the one-shot parse. Documents are assembled from a vocabulary of real
/// Markdown constructs (headings, lists, code, tables, math, quotes, alerts,
/// footnotes, inline mixes) and fed three ways — one byte at a time, in random
/// chunks, and as growing snapshots. A deterministic seed keeps failures
/// reproducible in CI.
final class StreamingFuzzTests: XCTestCase {

    /// A small deterministic PRNG (SplitMix64) so the fuzz corpus is reproducible.
    private struct RNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Markdown fragments the generator stitches together.
    private static let fragments: [String] = [
        "# Heading one\n",
        "## A sub heading\n",
        "Plain paragraph text that is reasonably long.\n",
        "Text with **bold**, *italic*, ~~strike~~, `code`, and a [link](https://e.com).\n",
        "Inline math $x^2 + y_i$ sits in this sentence with a citation [1].\n",
        "- bullet one\n- bullet two\n",
        "- a\n  - nested\n- b\n",
        "1. first\n2. second\n",
        "- [x] done\n- [ ] todo\n",
        "> a block quote\n",
        "> [!NOTE]\n> alert body text\n",
        "> [!WARNING]\n> careful now\n",
        "```swift\nlet x = 1\nprint(x)\n```\n",
        "    indented code line\n    second code line\n",
        "| a | b |\n|---|---|\n| 1 | 2 |\n",
        "$$e^{i\\pi} + 1 = 0$$\n",
        "---\n",
        "A footnote ref[^a].\n",
        "[^a]: footnote definition body.\n",
        "<div>\nraw html block\n</div>\n",
        "<table><tr><td>cell</td></tr></table>\n",
        "<br>\n",
        "Inline <span>html</span> in a paragraph.\n",
        "\n",
        "trailing text no newline",
    ]

    private func oneShot(_ source: String) -> Document {
        let blocks = BlockLexer.lex(Array(source.utf8)[...])
        return Document(blocks: InlineParser.resolveInlines(in: blocks, config: .default))
    }

    private func streamedByByte(_ source: String) -> Document {
        let parser = IncrementalParser()
        var offset = 0
        // Cut only at UTF-8 scalar boundaries (a partial scalar is never a real
        // streamed state).
        for scalar in source.unicodeScalars {
            let chunk = String(scalar)
            parser.consume(delta: chunk, at: offset)
            offset += chunk.utf8.count
        }
        if source.isEmpty { parser.consume(snapshot: "") }
        return parser.document
    }

    private func streamedBySnapshot(_ source: String) -> Document {
        let parser = IncrementalParser()
        var acc = ""
        for scalar in source.unicodeScalars {
            acc.unicodeScalars.append(scalar)
            parser.consume(snapshot: acc)
        }
        if source.isEmpty { parser.consume(snapshot: "") }
        return parser.document
    }

    private func streamedRandomChunks(_ source: String, rng: inout RNG) -> Document {
        let parser = IncrementalParser()
        let scalars = Array(source.unicodeScalars)
        var i = 0
        var offset = 0
        while i < scalars.count {
            let take = Int(rng.next() % 7) + 1
            let end = min(i + take, scalars.count)
            let chunk = String(String.UnicodeScalarView(scalars[i..<end]))
            parser.consume(delta: chunk, at: offset)
            offset += chunk.utf8.count
            i = end
        }
        if source.isEmpty { parser.consume(snapshot: "") }
        return parser.document
    }

    func testStreamingEquivalenceFuzz() {
        var rng = RNG(seed: 0x5DEE_CE66_D32A_17B3)
        let iterations = 250
        for iteration in 0..<iterations {
            // Assemble a random document from 1...8 fragments.
            let count = Int(rng.next() % 8) + 1
            var source = ""
            for _ in 0..<count {
                let frag = Self.fragments[Int(rng.next() % UInt64(Self.fragments.count))]
                source += frag
            }

            let expected = oneShot(source)
            let byByte = streamedByByte(source)
            let bySnap = streamedBySnapshot(source)
            let byRandom = streamedRandomChunks(source, rng: &rng)

            XCTAssertEqual(byByte, expected, "byte-delta diverged (iter \(iteration)) for:\n\(source)")
            XCTAssertEqual(bySnap, expected, "snapshot diverged (iter \(iteration)) for:\n\(source)")
            XCTAssertEqual(byRandom, expected, "random-chunk diverged (iter \(iteration)) for:\n\(source)")
        }
    }
}
