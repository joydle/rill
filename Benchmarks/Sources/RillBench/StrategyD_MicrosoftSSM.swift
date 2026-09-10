// Strategy D — microsoft/SwiftStreamingMarkdown (their shipping parser).
//
// Pinned by revision 947e958edf0d5b4352ac9383ec4de7a9bf8f13b9 (no release tags
// exist). We drive their actual `MarkdownParserImpl` through its public async
// `parse(text:)` convenience, which is the speculativeRewrite:false path:
//
//   parse(text:) -> parse(text:option: .init(speculativeRewrite: false)).document
//     -> latexPreprocessor.process(...) then Document(parsing: preprocessed)
//
// (see ms-ssm Sources/MarkdownText/Parser/MarkdownParser.swift:24-26 and
//  MarkdownParserImpl.swift:24-40). This is exactly what their turnkey
// `StreamedMarkdownView` runs per emission (StreamedMarkdownView.swift:88 calls
// `parser.parse(text:config:)`, which builds on `parse(text:)`), minus the
// SwiftUI render layer — i.e. the pure LaTeX-preprocess + cmark-gfm parse CPU cost.
//
// This runner is a FREE (nonisolated) async function on purpose: calling the
// nonisolated `parse` from a nonisolated context keeps the parsed `Document`
// inside one isolation domain, so it never has to cross an actor boundary. Only
// the Sendable `StrategyRun` is returned to the caller.

#if HAVE_MS_SSM
import SwiftStreamingMarkdown
import Markdown

/// Re-parse the WHOLE accumulated buffer on every chunk through Microsoft's real
/// `MarkdownParserImpl.parse(text:)`. O(document) per delta. Timed across the full
/// async call (the async chain has no suspension points, so the wall-clock is the
/// real parse cost).
func runMicrosoftSSM(chunks: [[UInt8]]) async -> StrategyRun {
    let clock = ContinuousClock()
    let parser = MarkdownParserImpl()
    var acc = ""
    var samples: [ChunkSample] = []
    var cumulative = 0.0
    for chunk in chunks {
        acc += String(decoding: chunk, as: UTF8.self)
        let t0 = clock.now
        let doc = await parser.parse(text: acc) // -> Markdown.Document
        let dt = (clock.now - t0).nanoseconds
        blackhole(doc.childCount)
        cumulative += dt
        samples.append(ChunkSample(accumulatedBytes: acc.utf8.count, nanos: dt))
    }
    return StrategyRun(cumulativeMs: cumulative / 1_000_000, samples: samples)
}
#endif
