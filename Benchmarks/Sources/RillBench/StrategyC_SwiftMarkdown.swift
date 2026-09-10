// Strategy C — swift-markdown full re-parse (Microsoft SSM's actual parsing core).
//
// Kept in its OWN file that imports `Markdown`. This is deliberate: MarkdownUI
// (strategy E) exports a `public struct Markdown: View` that shadows the `Markdown`
// MODULE, so `import Markdown` and `import MarkdownUI` must never live in the same
// file. Each competitor gets its own translation-unit-scoped imports.

#if HAVE_SWIFT_MARKDOWN
import Markdown

/// Re-parse the WHOLE accumulated buffer on every chunk with swift-markdown 0.7.3
/// (`Document(parsing:)` through cmark-gfm) — exactly what `SwiftStreamingMarkdown`
/// does per emission. O(document) per delta.
func runSwiftMarkdownFullReparse(chunks: [[UInt8]]) -> StrategyRun {
    let clock = ContinuousClock()
    var acc = ""
    var samples: [ChunkSample] = []
    var cumulative = 0.0
    for chunk in chunks {
        acc += String(decoding: chunk, as: UTF8.self)
        let t0 = clock.now
        let doc = Markdown.Document(parsing: acc)
        let dt = (clock.now - t0).nanoseconds
        blackhole(doc.childCount)
        cumulative += dt
        samples.append(ChunkSample(accumulatedBytes: acc.utf8.count, nanos: dt))
    }
    return StrategyRun(cumulativeMs: cumulative / 1_000_000, samples: samples)
}
#endif
