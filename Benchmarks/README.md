# Rill Benchmarks

A separate SwiftPM package (not part of the main Rill package graph) that measures
Rill's incremental streaming parser against full-reparse strategies — the approach a
non-incremental Markdown renderer uses when it re-parses each streamed snapshot.

This is the only place external dependencies are used. The main Rill package has none.
Nothing here modifies the main package; it only links it.

## Run

```bash
cd Benchmarks
swift run -c release RillBench                # full matrix, writes RESULTS.md
swift run -c release RillBench --diagnostic   # per-delta dirty-tail trace
swift run -c release RillBench out.md         # write the report to a custom path
```

Use a release build; debug numbers are not meaningful. The competitor strategies fetch
their dependencies over the network on first run — see offline mode below.

## What it measures

For synthetic Markdown documents (headings, paragraphs, bulleted and numbered lists,
fenced code, GFM tables, block quotes) at increasing sizes (1/4/16/64 KB), streamed in
fixed 256-byte chunks, it records the cumulative wall-clock time to process the whole
stream and the per-delta time as a function of current document size for:

- **A — Rill incremental:** `IncrementalParser.consume(delta:at:)`. O(tail) per delta.
- **B — Rill full re-parse:** `InlineParser.resolveInlines(in: BlockLexer.lex(wholeBuffer))`
  on every chunk, using Rill's own parser to isolate the algorithmic difference from
  implementation differences. O(document) per delta.
- **C — swift-markdown full re-parse:** `Markdown.Document(parsing:)` on every chunk
  (swift-markdown 0.7.3, the cmark-gfm parsing core `SwiftStreamingMarkdown` builds on).
- **D — microsoft/SwiftStreamingMarkdown:** `MarkdownParserImpl().parse(text:)` on every
  chunk, pinned to revision `947e958`. Driven through their public async parser — the
  `speculativeRewrite:false` path that runs their LaTeX preprocessor then
  `Document(parsing:)`, which is what their `StreamedMarkdownView` executes per emission.
  Scoped to parse and convert CPU cost; their SwiftUI render layer is out of scope.
- **E — MarkdownUI full re-parse:** `MarkdownContent(_:)` on every chunk (MarkdownUI 2.4.1,
  via its own swift-cmark 0.8.0).
- **F — Apple `AttributedString(markdown:)`:** Foundation's built-in parse.
  ⚠️ A lossy, flattening parse (a flat run list, not a block AST) — see `RESULTS.md`.

The `microsoft/SwiftStreamingMarkdown` package builds headless on macOS (it declares
`.macOS(.v14)` and ships an AppKit `NSTextView` renderer), so strategy D runs its actual
parser rather than a stand-in.

## Offline mode

A and B require only the local Rill package and always build and run offline; F needs
only Foundation. The competitor strategies C, D, and E are each gated by an `enable*`
flag and a compile-time `#if` in `Package.swift` (`enableSwiftMarkdown`,
`enableMarkdownUI`, `enableMicrosoft`). Set any to `false` to build without network — the
benchmark still compiles and runs with the remaining strategies, and the report records
which were skipped.

See [`RESULTS.md`](RESULTS.md) for captured numbers, per-delta curves, and dependency
pins.
