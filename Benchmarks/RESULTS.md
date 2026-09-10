# Rill Streaming-Parse Benchmark — Results

Cumulative parse time for **Rill incremental** compared with **full re-parse** strategies (Rill's own parser, SwiftStreamingMarkdown, swift-markdown, MarkdownUI, and Apple's built-in).
Run with `swift run -c release` from the `Benchmarks/` directory.

## Method

- Synthetic Markdown (headings, paragraphs, bulleted/numbered lists, fenced code, GFM tables, block quotes) generated at increasing target sizes.
- Each document is streamed in fixed **256-byte chunks** (so the number of chunks K grows with size). After each chunk the wall-clock time is measured to (re)process the stream up to that point.
- **Cumulative ms** = sum of all per-delta times across the whole stream.
- Every strategy accumulates the same byte chunks and, except for A, re-parses the whole buffer each chunk, matching snapshot semantics.
- Each strategy is warmed up 1x and measured 3x; the **minimum** cumulative time is reported (least-noise estimate). `ContinuousClock`, results blackholed against dead-code elimination.

### Strategies

- **A — Rill incremental:** `IncrementalParser.consume(delta:at:)`. Freezes a committed prefix of closed blocks; re-lexes only the dirty tail. **O(tail) per delta.**
- **B — Rill full re-parse:** `InlineParser.resolveInlines(in: BlockLexer.lex(wholeBuffer))` on every chunk, using Rill's own parser. Simulates snapshot semantics to isolate the algorithmic difference from implementation differences. **O(document) per delta.**
- **C — swift-markdown full re-parse:** `Markdown.Document(parsing: wholeBufferSoFar)` on every chunk (swift-markdown 0.7.3, the same pin used by `microsoft/SwiftStreamingMarkdown`). This is the cmark-gfm parsing core that package builds on. **O(document) per delta.**
- **D — microsoft/SwiftStreamingMarkdown:** `MarkdownParserImpl().parse(text:)` on every chunk, pinned to revision `947e958edf0d5b4352ac9383ec4de7a9bf8f13b9` (no release tags exist). Driven through their public async parser API — the `speculativeRewrite:false` path that runs their LaTeX preprocessor then `Document(parsing:)`, which is what their `StreamedMarkdownView` executes per emission (`MarkdownParser.swift:24-26`, `MarkdownParserImpl.swift:24-40`). Scoped to parse/convert CPU cost; the SwiftUI render layer is out of scope. **O(document) per delta.**
- **E — MarkdownUI full re-parse:** `MarkdownContent(wholeBufferSoFar)` on every chunk (MarkdownUI 2.4.1, gonzalezreal/swift-markdown-ui, via its own swift-cmark 0.8.0). The parse-cost analog of `Document(parsing:)`; no View built, nothing rendered. **O(document) per delta.**
- **F — Apple `AttributedString(markdown:)`:** Foundation's built-in, zero-dependency parse of the whole buffer each chunk (`interpretedSyntax: .full`, `failurePolicy: .returnPartiallyParsedIfPossible`). **O(document) per delta.** ⚠️ **Lossy/flattening caveat below.**

Strategies A and B use only the local zero-dependency Rill package and always build and run offline. F needs only Foundation. C, D, E are gated behind `#if HAVE_SWIFT_MARKDOWN` / `HAVE_MS_SSM` / `HAVE_MARKDOWN_UI` and are skipped cleanly if their dependency can't be fetched.

## Cumulative wall-clock time (ms) to process the whole stream

| Doc size | Bytes | Chunks (K) | A: Rill incremental | B: Rill full-reparse | C: swift-markdown | D: Microsoft SSM | E: MarkdownUI | F: AttributedString | B/A | C/A | D/A | E/A | F/A |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 KB | 1099 | 5 | 0.381 | 0.623 | 0.297 | 0.854 | 0.098 | 2.108 | 1.634x | 0.781x | 2.240x | 0.258x | 5.533x |
| 4 KB | 4347 | 17 | 0.684 | 3.525 | 2.325 | 6.414 | 0.738 | 15.314 | 5.156x | 3.401x | 9.380x | 1.079x | 22.395x |
| 16 KB | 16557 | 65 | 1.701 | 42.961 | 30.102 | 86.886 | 9.338 | 210.589 | 25.256x | 17.696x | 51.078x | 5.490x | 123.800x |
| 64 KB | 65547 | 257 | 9.013 | 648.471 | 443.383 | 1357.028 | 144.397 | 3471.909 | 71.950x | 49.195x | 150.566x | 16.021x | 385.218x |

## Per-delta time vs current document size (largest doc: 64 KB, K=257 chunks)

A stays roughly flat (O(tail)) while every full re-parse strategy grows with document size (O(document)).

| Accumulated size (KB) | A per-delta (ms) | B per-delta (ms) | C per-delta (ms) | D per-delta (ms) | E per-delta (ms) | F per-delta (ms) |
|---:|---:|---:|---:|---:|---:|---:|
| 8.000 | 0.0147 | 0.6644 | 0.4279 | 1.2788 | 0.1382 | 3.1384 |
| 16.000 | 0.0245 | 1.2661 | 0.8569 | 2.6792 | 0.2746 | 6.9573 |
| 24.000 | 0.0344 | 1.9107 | 1.2750 | 3.9351 | 0.4054 | 9.7585 |
| 32.000 | 0.0373 | 2.5006 | 1.7026 | 5.4677 | 0.5485 | 13.2179 |
| 40.000 | 0.0284 | 3.2237 | 2.1179 | 6.5395 | 0.6813 | 16.7712 |
| 48.000 | 0.0370 | 3.7489 | 2.6030 | 7.9494 | 0.8153 | 20.0379 |
| 56.000 | 0.0502 | 4.3858 | 3.0025 | 9.0297 | 0.9458 | 23.5344 |
| 64.011 | 0.0515 | 4.9189 | 3.4249 | 10.1639 | 1.0775 | 26.9512 |

## Growth analysis

- From 1 KB to 64 KB the document grew 60x.
- Strategy A (incremental) cumulative time grew **23.7x**, roughly linear in total bytes streamed (O(N)).
- Strategy B (Rill full re-parse) cumulative time grew **1042x**, super-linear, consistent with O(N^2/chunk).
- At 64 KB, cumulative time for Rill incremental compared with each full re-parse strategy:
    - 71.9x lower than Rill full-reparse (B), which grew 1042x over the same range.
    - 49.2x lower than swift-markdown (C), which grew 1491x over the same range.
    - 150.6x lower than Microsoft SSM (D), which grew 1590x over the same range.
    - 16.0x lower than MarkdownUI (E), which grew 1470x over the same range.
    - 385.2x lower than AttributedString (F), which grew 1647x over the same range.

The difference between O(tail) and O(document) per-delta cost is reproduced across five independent full-reparse implementations, and the ratio widens as documents grow.

## Strategy notes

- **C (swift-markdown) ran.** swift-markdown 0.7.3 (the pin used by `microsoft/SwiftStreamingMarkdown`) fetched and built; `Markdown.Document(parsing:)` is the cmark-gfm call that package uses.
- **D (`microsoft/SwiftStreamingMarkdown`) ran**, pinned to revision `947e958`. The package builds headless on macOS: it declares `.macOS(.v14)` and ships an AppKit `NSTextView`-based renderer. Strategy D times `MarkdownParserImpl.parse(text:)` (the `speculativeRewrite:false` → LaTeX-preprocess → `Document(parsing:)` path their `StreamedMarkdownView` runs per emission). D is scoped to parse and convert CPU cost; render-layer smoothness requires a window and is out of scope.
- **E (MarkdownUI 2.4.1) ran** via its own swift-cmark 0.8.0. `MarkdownContent(_:)` performs the pure O(document) cmark-gfm parse into MarkdownUI's block AST — no SwiftUI `View` is built.
- **F (Apple `AttributedString(markdown:)`) ran** (no dependency). ⚠️ **Caveat:** this is a lossy, flattening parse — it returns a single flat `AttributedString` (a run list), not a navigable block AST, and it flattens or drops block constructs (lists collapse, tables lose structure). It still scans the whole document O(N) per chunk, so it is a valid lightest-weight O(document) baseline, but a lower time reflects a simpler parse doing less structural work, not a faster equivalent parse. It is included as the built-in baseline, not as a like-for-like structural parser.

## Corpus & reproducibility notes

- The synthetic corpus is well-formed, blank-line-separated Markdown. Adjacent blocks are separated by a blank line so Rill's commit engine can freeze closed blocks; its commit boundaries are defined at blank lines and closing fences (see [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)).
- Strategies A and B call the shipping Rill APIs (`IncrementalParser`, `BlockLexer`, `InlineParser`) directly; C, D, E, and F call each library's public API.
- Corpus detail: list blocks are written so the list items immediately follow their heading (no blank line between the heading and the first `-`/`1.`). Rill's commit boundary is deliberately conservative about a blank line that *immediately precedes* a list marker (it could be a loose-list separator that would bind two sibling items into one list), so it keeps such a tail open. Placing the list directly after its heading routes it through the commit engine's list branch, which commits the whole list once it closes. Corpora that separate every block with a blank line will leave trailing lists uncommitted for longer and shift strategy A's numbers upward.
- All strategies see byte-identical input: `IncrementalParser.consume(delta:at:)` is fed the raw byte chunks; the full-reparse strategies accumulate the same bytes and re-process the whole buffer each chunk.
- Dependency pins for reproducibility: swift-markdown `0.7.3`, swift-cmark `0.8.0` (shared by C and E), MarkdownUI `2.4.1`, microsoft/SwiftStreamingMarkdown revision `947e958edf0d5b4352ac9383ec4de7a9bf8f13b9`.
- Environment: Swift 6.3, release build (`-c release`), arm64 macOS. Absolute numbers vary by machine; the ratios and growth curves are the reproducible result.
