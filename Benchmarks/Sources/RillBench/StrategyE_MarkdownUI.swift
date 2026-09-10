// Strategy E — MarkdownUI 2.4.1 (gonzalezreal/swift-markdown-ui), a widely-used
// SwiftUI markdown renderer. Uses its OWN swift-cmark 0.8.0 parse.
//
// Kept in its OWN file that imports `MarkdownUI`. MarkdownUI exports a
// `public struct Markdown: View` that shadows the `Markdown` MODULE, so this
// import must never share a file with `import Markdown` (strategies C and D).
//
// `MarkdownContent(_:)` (public unlabeled `init(_ markdown: String)`) performs the
// pure O(document) cmark-gfm parse into MarkdownUI's block AST — the parse-cost
// analog of `Document(parsing:)`, with no View built and nothing rendered.

#if HAVE_MARKDOWN_UI
import MarkdownUI

/// Re-parse the WHOLE accumulated buffer on every chunk with MarkdownUI's
/// `MarkdownContent(_:)`. O(document) per delta.
func runMarkdownUIFullReparse(chunks: [[UInt8]]) -> StrategyRun {
    let clock = ContinuousClock()
    var acc = ""
    var samples: [ChunkSample] = []
    var cumulative = 0.0
    for chunk in chunks {
        acc += String(decoding: chunk, as: UTF8.self)
        let t0 = clock.now
        let content = MarkdownContent(acc)
        let dt = (clock.now - t0).nanoseconds
        // `blocks` is internal; `childContent` is the public DCE barrier.
        blackhole(content.childContent == nil ? 0 : 1)
        cumulative += dt
        samples.append(ChunkSample(accumulatedBytes: acc.utf8.count, nanos: dt))
    }
    return StrategyRun(cumulativeMs: cumulative / 1_000_000, samples: samples)
}
#endif
