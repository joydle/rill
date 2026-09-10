# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-10

Initial public release: a dependency-free incremental streaming Markdown
library for SwiftUI (iOS 18+ / macOS 15+), Swift 6 strict concurrency. The
public API is stable under SemVer from this release.

### Added

- **`RillCore`** — Foundation-only AST and the incremental "stable-prefix"
  streaming engine.
  - `Document`, `Block`, `Inline`, and supporting value types (`Heading`,
    `Paragraph`, `List`, `ListItem`, `CodeBlock`, `Table`, `Link`, `Image`,
    `Citation`), all `Sendable` and `Hashable`, identified by a stable
    content-derived `NodeID`.
  - `IncrementalParser` with `commitIndex` advance and `NodeID` memoization:
    re-lexes only the dirty tail per delta (O(tail), not O(document)).
  - `MarkdownStreamConsumer` with snapshot and append-delta entry points;
    `ParseConfig`.
  - Block lexer and inline parser covering a CommonMark + GFM subset:
    headings, paragraphs, nested/tight/loose lists, task lists,
    blockquotes, fenced and indented code, pipe tables with alignment,
    thematic breaks, math blocks, emphasis, strikethrough, code spans, links,
    autolinks, images, citations, inline math, **GFM footnotes**, and
    **GitHub alerts** (`> [!NOTE]`/`TIP`/`IMPORTANT`/`WARNING`/`CAUTION`).
  - Streaming-equivalence guarantee: chunked parsing produces a `Document`
    byte-identical to a one-shot parse, for any chunking.
  - **Hardening:** bounded recursion in the block lexer (nested blockquotes,
    lists, footnote bodies), the inline parser (nested-link recursion cap plus a
    defensive bounds clamp), and the math parser, so adversarial nesting (deep
    blockquotes, `[[[…]]]`, chained footnotes) degrades to literal text instead
    of overflowing the stack.
- **`RillMath`** — Foundation-only native LaTeX rendering.
  - `MathLexer` tokenizer, `MathParser`, and `MathCommandTable` (337 mapped
    commands) producing a `MathNode` tree, with `.unknown` degradation for
    unmapped names.
  - TeX-style box layout (`MathBox`, `MathLayout`, `MathStyle`, `MathMetrics`):
    fractions, scripts, radicals, big operators with limit placement, matrices,
    and accents.
- **`RillAnalytics`** — Foundation-only telemetry.
  - `MarkdownAnalytics` `Sendable` protocol; `ParseMetrics`, `RenderMetrics`,
    and the `MarkdownInteraction` enum.
  - Sinks: `NoopAnalytics` (default), `OSLogAnalytics` (`os.signpost`
    intervals for Instruments), and `MultiplexAnalytics`.
- **`RillUI`** — the SwiftUI renderer.
  - `MarkdownView` (static), `DocumentView` (pre-parsed), and
    `StreamingMarkdownView` driven by an `@Observable` `MarkdownSource`.
  - Stable-identity rendering: committed blocks are `Equatable`-gated by
    `NodeID`, so only the live tail re-renders; render accounting via
    `RenderMetrics`.
  - SwiftUI-native word-fade append animation for the streaming tail,
    configurable via `RenderConfig`.
  - Themed GitHub-alert callouts and a footnotes section renderer.
  - `RillTheme` (fonts, colors, metrics, code-block style) with a fully
    populated `default`; `RenderConfig` (animation, citation resolver, link
    handler, `ImageLoading`).
  - Per-block and per-inline renderers, citation pills, native math rendering
    (`MathView` plus the `MathBoxRenderer` box-flattening pass), and table/code
    copy interactions.
  - `CodeHighlighter` protocol and `RillSyntax` default highlighter with
    grammars for Swift, JavaScript/TypeScript, Python, JSON, Bash, HTML, and
    Rust, plus a generic fallback; results memoized.
- Four layered SPM library products with a layering guard test ensuring the
  pure-logic modules never import SwiftUI or UIKit.
- Three runnable sample apps: `Examples/RillChat`, a native iOS AI-chat client
  that streams answers token-by-token through a `MarkdownSource` (the source of
  the README demos); `Examples/RillDemo`, a macOS app with a chunked-streaming
  simulator, theme switcher, and a live analytics HUD; and `Examples/RillDemoiOS`,
  a thin iOS Simulator wrapper (xcodegen-generated) around the shared demo kit.
- Property-based streaming-equivalence fuzz: a fixed corpus plus hundreds of
  randomly-assembled documents, each fed three ways (byte-by-byte, random
  chunks, and growing snapshots) with UTF-8-boundary cuts, all asserted
  byte-identical to a one-shot parse.
- Triple-slash documentation comments on every public symbol.
- MIT license, README, contributing guide, and CI running `swift build` and
  `swift test` on macOS.
- `Benchmarks/` package — a reproducible streaming-parse benchmark of Rill's
  incremental parser against five full-reparse strategies: Rill's own parser,
  [swift-markdown](https://github.com/swiftlang/swift-markdown),
  [microsoft/SwiftStreamingMarkdown](https://github.com/microsoft/SwiftStreamingMarkdown),
  [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui), and Apple's
  `AttributedString(markdown:)` — with results and method in
  [`Benchmarks/RESULTS.md`](Benchmarks/RESULTS.md).
- `docs/COMPARISON.md` — a `file:line`-cited feature and dependency comparison
  with `microsoft/SwiftStreamingMarkdown`, and `docs/ARCHITECTURE.md` — how the
  streaming engine works internally.

[1.0.0]: https://github.com/joydle/rill/releases/tag/v1.0.0
