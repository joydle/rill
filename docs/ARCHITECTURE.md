# How Rill Works

> The internals of Rill's streaming engine: the AST, the match that locates and
> reuses unchanged content, and how the same identity gates rendering. Claims
> below are cited at `file:line`.

Rill is a streaming Markdown engine. The design answers one question: when text
is appended, how is re-parsing and re-rendering the whole document avoided? The
approach is to do work proportional to the *dirty tail* (the unfinished part at
the end) rather than the whole buffer — `O(tail)` instead of `O(document)`.

The package is four layered products, but the AST and matching logic live almost
entirely in `RillCore`:

```
RillAnalytics   Foundation only · metrics, protocol, sinks
RillMath        Foundation only · LaTeX tokenizer + math box layout
RillCore        Foundation only · AST + incremental parser   → depends on RillAnalytics
RillUI          SwiftUI · renders AST → views, theming, math, syntax highlight
                → depends on RillCore, RillMath, RillAnalytics
```

No module except `RillUI` imports SwiftUI/UIKit (compiler- and test-enforced).

---

## 1. The AST

The parsed document is a tree of pure value types. The top of it is `Block`
(`Sources/RillCore/Model/Block.swift`) — an `indirect enum` with one case per
Markdown construct:

```swift
public indirect enum Block: Sendable, Hashable {
    case heading(Heading)
    case paragraph(Paragraph)
    case blockQuote(BlockQuote)
    case alert(Alert)
    case list(List)
    case codeBlock(CodeBlock)
    case table(Table)
    case thematicBreak
    case mathBlock(MathBlock)
    case htmlBlock(HTMLBlock)
    case footnoteDefinition(FootnoteDefinition)
}
```

It is `Sendable` + `Hashable`, pure data, with no view-layer types anywhere.

### Content-derived identity: `NodeID`

Each `Block` exposes a content-derived identity, `NodeID`
(`Sources/RillCore/Model/NodeID.swift`). Everything downstream depends on it:

- It is a **seedless FNV-1a 64-bit digest** of the block's case tag plus
  payload — deliberately *not* `Swift.Hasher`, whose seed is randomized per
  process. Rill needs the digest to be identical across launches and machines so
  identity is reproducible.
- Each enum case folds in a per-case **discriminator tag** first, so
  `.code("x")` and `.text("x")` can never collide (`Block.hash(into:)`,
  `Block.swift:61`).
- Strings are **length-framed** before their bytes, so concatenation
  ambiguities (`"ab" + "c"` vs `"a" + "bc"`) cannot alias
  (`ContentHasher.combine(_:)`, `NodeID.swift:56`).
- Optionals fold a tag that distinguishes `nil` from `""` / `0` / `false`.

The single guarantee that everything downstream relies on:

> **Equal content → equal `NodeID`.**

`Block` intentionally does **not** conform to `Identifiable`: two `---` rules
share a `NodeID`, so it is a *content* key, not a *position* key. Render a
`[Block]` with a position-based key, e.g.
`ForEach(Array(blocks.enumerated()), id: \.offset)`.

---

## 2. How Rill knows what to re-parse

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/diagrams/commit-boundary-dark.svg">
  <img alt="A buffer of Markdown blocks. Four closed blocks left of commitIndex are frozen and reused; the open paragraph to its right is the dirty tail, the only region re-lexed on each delta." src="images/diagrams/commit-boundary-light.svg" width="100%">
</picture>

The streaming engine is `IncrementalParser`
(`Sources/RillCore/Streaming/IncrementalParser.swift`). It holds the buffer plus
a frozen prefix:

| State | Meaning |
| --- | --- |
| `buffer: [UInt8]` | All text consumed so far, as UTF-8 bytes |
| `commitIndex: Int` | Byte offset past the last **definitively-closed** block |
| `committedBlocks: [Block]` | The frozen, fully-resolved blocks for `[0, commitIndex)` |
| `memo: [NodeID: Block]` | Content-keyed cache of resolved blocks |

A delta arrives via `consume(delta:at:)` (append-delta wire format) or
`consume(snapshot:)` (full growing snapshot). Locating the work is two matches
stacked:

### Match A — byte-level (find the dirty point)

`commonPrefixLength(old, new)` (`IncrementalParser.swift:204`) walks both byte
arrays until they diverge, returning `dirtyStart` — the first byte that actually
changed:

```swift
private static func commonPrefixLength(_ a: [UInt8], _ b: [UInt8]) -> Int {
    let n = min(a.count, b.count)
    var i = 0
    while i < n, a[i] == b[i] { i += 1 }
    return i
}
```

For append-only streaming `dirtyStart` is simply the old buffer length, so
nothing before it is touched. It also makes re-emitting the same `(delta,
offset)` pair idempotent.

### Match B — block-level (the commit boundary)

`CommitBoundary.lastClosedIndex(in:)`
(`Sources/RillCore/Parser/CommitBoundary.swift`) scans the dirty tail
line-by-line and asks: *what is the last point I can freeze forever?* A position
is a safe boundary only when nothing arriving later could change it:

- **paragraph** closed by a blank line,
- **fenced code** closed by its matching closing fence (at the same indent),
- **math block** closed by `$$` / `\]`,
- **heading / thematic break** — single-line atoms that cannot be extended.

Constructs that *block* committing keep the tail open:

- an **unterminated fence or math block** — nothing past it commits,
- the **trailing** paragraph / list / table — a future line could extend it via
  lazy continuation or a new table row.

The subtle rules all exist to preserve **streaming equivalence** (see §4). For
example, the scanner will not commit across a blank line if the next non-blank
line starts a list marker, because that blank may be a *loose-list separator*
binding two sibling items into one list — committing there would split the list
and diverge from a one-shot parse (`CommitBoundary.swift:85`,
`nextNonBlankStartsList`). Indented-code interior blanks, fences opened inside a
list item, and unterminated trailing lines are handled with the same
conservative discipline.

### The parse pass

`parse(dirtyStart:)` (`IncrementalParser.swift:117`) ties the two matches
together:

1. **Roll back if needed.** If `dirtyStart < commitIndex` (an edit landed inside
   frozen territory), drop the committed prefix and recommit from the change
   point. The `memo` survives — it is content-keyed, so unchanged blocks
   re-encountered during recommit reuse their cached values
   (`rollBack(to:)`, `IncrementalParser.swift:191`).
2. **Commit newly-closed blocks.** Lex only `[commitIndex, newBoundary)`, and
   for each closed block check `memo[block.id]` **before** resolving its
   inlines. Identical bytes ⇒ cache hit ⇒ `InlineParser` never runs again for
   that block (`IncrementalParser.swift:144`).
3. **Re-lex the open tail.** Lex `[commitIndex, end)` fresh — this is the only
   part that is actually `O(tail)`.
4. **Publish + measure.** Set `document = committedBlocks + tailBlocks`, fire
   `onUpdate`, and emit `ParseMetrics` (`dirtyTailBytes`, `totalBytes`,
   `blocksCommitted`, `blocksReused`).

So the mechanism is a byte-prefix match to locate the change, plus a `NodeID`
content match to reuse parse work for anything unchanged.

---

## 3. The same match pays off at render time

The identity that saved parse work also gates SwiftUI re-rendering.
`EquatableBlockView` (`Sources/RillUI/Blocks/EquatableBlockView.swift`) declares
two views equal **iff their blocks share a `NodeID`**:

```swift
public nonisolated static func == (lhs: EquatableBlockView, rhs: EquatableBlockView) -> Bool {
    lhs.block.id == rhs.block.id
}
```

Wrapped in an `EquatableView`, SwiftUI elides `body` evaluation for any
committed block whose identity is unchanged. Only the live tail block — whose
content, and therefore `NodeID`, changed — re-renders. The render environment
(theme/config/analytics) is deliberately **excluded** from equality so it does
not defeat skipping.

`DocumentRenderPlan` (`Sources/RillUI/Blocks/DocumentRenderPlan.swift`) mirrors
this decision purely from the model — diffing the current document's block ids
against the previous pass's using a `Multiset<NodeID>` so two identical sibling
blocks match one-for-one rather than collapsing to a single skip. This is what
the analytics HUD reports as "blocks reused vs re-rendered"; the counts are
derived from the model, not from the view layer.

---

## 4. End-to-end flow

```
delta ─▶ commonPrefixLength ─▶ dirtyStart
      ─▶ (rollBack if dirtyStart < commitIndex)
      ─▶ CommitBoundary.lastClosedIndex ─▶ newBoundary
      ─▶ commit [commitIndex, newBoundary):
             BlockLexer.lex → memo[NodeID] (hit?) → InlineParser (miss only)
      ─▶ re-lex open tail [commitIndex, end)      ← the only O(tail) work
      ─▶ Document(committedBlocks + tailBlocks)
      ─▶ SwiftUI: EquatableBlockView gated by NodeID → tail-only re-render
```

### The streaming-equivalence invariant

For **any** input and **any** chunking, the final `Document` is byte-identical
to a one-shot parse:

```
IncrementalParser(streamed in any chunks)  ==  InlineParser.resolveInlines(in: BlockLexer.lex(...))
```

Every conservative rule in `CommitBoundary` exists to preserve this property:
the engine would rather keep something in the live tail than commit it wrong.
The invariant is property-tested over a corpus plus hundreds of
randomly-assembled documents, each fed byte-by-byte, in random chunks, and as
growing snapshots, with UTF-8-boundary fuzz.

---

## Why per-delta cost stays flat

A full-reparse renderer does `O(document)` work per delta, so the per-delta cost
climbs as the response grows and finished content re-renders on every token.
Rill's per-delta cost is `O(dirty tail)`, and the committed prefix is both
parse-memoized (`memo[NodeID]`) and render-skipped (`EquatableBlockView`), so the
per-delta cost does not grow with the length of the committed document.

See [`../Benchmarks/RESULTS.md`](../Benchmarks/RESULTS.md) for measurements and
[`COMPARISON.md`](COMPARISON.md) for the comparison with
`microsoft/SwiftStreamingMarkdown`.
