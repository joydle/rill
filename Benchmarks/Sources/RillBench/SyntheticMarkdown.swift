import Foundation

/// Deterministic synthetic Markdown generator.
///
/// Produces realistic LLM-style Markdown — headings, paragraphs, bulleted and
/// numbered lists, fenced code, and GFM tables — repeated until the UTF-8 byte
/// length reaches (or just exceeds) a target size. The output is fully closed
/// (every block terminated) so the one-shot and streamed parses are well-formed.
enum SyntheticMarkdown {

    /// A repeating catalogue of well-formed block "sections". Concatenated in
    /// order and cycled until the target byte budget is hit.
    private static let sections: [String] = [
        """
        # Section Heading: Streaming Markdown Internals

        This paragraph describes how an incremental parser commits a stable prefix
        of closed blocks while only re-lexing the dirty tail. It contains **bold**,
        *italic*, `inline code`, and a [link](https://example.com) so the inline
        scanner has real work to do on every pass.

        """,
        // Note: the list follows its heading with no intervening blank line. This
        // is valid CommonMark (a heading and a list are distinct blocks) and is
        // common in LLM output. It also routes through Rill's list commit branch
        // cleanly — Rill's commit engine is deliberately conservative about a blank
        // line that immediately precedes a list marker (it could be a loose-list
        // separator), so blank-then-list keeps the whole list in the open tail.
        """
        ## Bulleted List
        - First item with some descriptive trailing text for length.
        - Second item that mentions `tail` re-lexing and *emphasis*.
        - Third item with a [reference](https://rill.dev) and **strong** run.
        - Fourth item closing the list cleanly before a blank line.

        """,
        """
        ### Numbered Steps
        1. Normalize the incoming delta into the growing UTF-8 buffer.
        2. Find the new dirty start at the previous commit boundary.
        3. Re-lex only the dirty tail into candidate blocks.
        4. Advance the commit index past every newly closed block.

        """,
        """
        Here is a fenced code block that the lexer must scan line-by-line until it
        finds the closing fence:

        ```swift
        func consume(delta: String, at offset: Int) {
            buffer.replaceSubrange(offset..., with: Array(delta.utf8))
            parse(dirtyStart: offset)
        }
        ```

        """,
        """
        And a GFM table with column alignment that the block lexer recognizes:

        | Strategy | Per-delta cost | Whole-stream cost |
        | :------- | :------------: | ----------------: |
        | Rill incremental | O(tail) | O(N) |
        | Full reparse | O(document) | O(N^2 / chunk) |
        | swift-markdown | O(document) | O(N^2 / chunk) |

        """,
        """
        > A block quote summarizing the thesis: Microsoft re-parses the entire
        > snapshot on every emission, which is O(document) per delta. Rill freezes
        > committed blocks and touches only the open tail, which is O(tail).

        """,
    ]

    /// Generates Markdown whose UTF-8 length is at least `targetBytes`.
    ///
    /// Each section is normalized to be terminated by a blank line, so adjacent
    /// blocks are always separated by a blank line — the well-formed shape real
    /// LLM output uses and the shape Rill's commit engine is designed for. (Swift
    /// multiline string literals collapse a section's trailing blank line to a
    /// single newline, so we re-add it explicitly here.)
    static func generate(targetBytes: Int) -> String {
        var out = ""
        var i = 0
        while out.utf8.count < targetBytes {
            let section = sections[i % sections.count]
                .trimmingCharacters(in: .newlines)
            out += section + "\n\n"
            i += 1
        }
        return out
    }
}
