import Foundation

/// A single Markdown document that exercises every block and inline feature Rill
/// renders, used by the demo as the text the streaming simulator replays.
///
/// The content deliberately includes headings, tight/loose and task lists, a GFM
/// table with column alignment, a fenced code block, a blockquote, inline and
/// block math, citations, links, and emphasis/strong/strikethrough/inline-code —
/// so streaming it shows the full renderer and the analytics HUD has plenty of
/// blocks to commit and reuse.
public enum ShowcaseDocument {

    /// The showcase Markdown text.
    public static let markdown: String = """
    # Rill — Streaming Markdown

    Rill renders Markdown that arrives **token by token** from an LLM, re-lexing
    only the *dirty tail* so finished blocks never re-render. This document streams
    in chunk by chunk to show it off [1].

    ## Features at a glance

    - Incremental, stable-prefix parsing
    - Zero dependencies — pure Swift + SwiftUI
    - Native LaTeX with a real box-layout engine
    - Rich ~~basic~~ streaming analytics [2]

    ### A task list

    - [x] Block lexer
    - [x] Incremental engine
    - [ ] Your next great idea

    ## Benchmarks

    | Strategy | Per-delta cost | Dependencies |
    | :------- | :------------: | -----------: |
    | Full re-parse | O(document) | varies |
    | Rill | O(tail) | none |

    ## Some code

    ```swift
    func greet(_ name: String) -> String {
        // a friendly hello
        return "Hello, \\(name)!"
    }
    ```

    > Rill freezes a committed prefix of closed blocks and only re-lexes the live
    > tail — O(tail) per delta instead of O(document).

    ## A little math

    The Gaussian integral is $\\int_{-\\infty}^{\\infty} e^{-x^2}\\,dx = \\sqrt{\\pi}$,
    and a classic identity renders as a block:

    $$
    e^{i\\pi} + 1 = 0
    $$

    See the [project README](https://example.com/rill) for the full story [3].
    """
}
