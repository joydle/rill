// Strategy F — Apple Foundation `AttributedString(markdown:)`, the zero-dependency
// built-in baseline. Only imports Foundation, so it is ALWAYS available.
//
// Caveat (also recorded in RESULTS.md): this is a lossy, flattening parse.
// It returns a single flat `AttributedString` (a run list), NOT a navigable block
// AST — block constructs are flattened/dropped (lists collapse, tables lose
// structure). It still scans the whole document O(N) per chunk, so it is a fair
// lightest-weight O(document) baseline, but a lower time reflects a SIMPLER parse
// doing LESS structural work, not a faster equivalent parse.

import Foundation

/// Re-parse the WHOLE accumulated buffer on every chunk with Apple's built-in
/// `AttributedString(markdown:options:)`. O(document) per delta (lossy/flattening).
func runAttributedStringFullReparse(chunks: [[UInt8]]) -> StrategyRun {
    let clock = ContinuousClock()
    var acc = ""
    var samples: [ChunkSample] = []
    var cumulative = 0.0
    let opts = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: true,
        interpretedSyntax: .full,
        failurePolicy: .returnPartiallyParsedIfPossible
    )
    for chunk in chunks {
        acc += String(decoding: chunk, as: UTF8.self)
        let t0 = clock.now
        // `try?`: a partial-parse failure should never abort the benchmark; the
        // parse work (the O(document) scan we are timing) has still happened.
        let runsCount = (try? AttributedString(markdown: acc, options: opts))?.runs.count ?? 0
        let dt = (clock.now - t0).nanoseconds
        blackhole(runsCount)
        cumulative += dt
        samples.append(ChunkSample(accumulatedBytes: acc.utf8.count, nanos: dt))
    }
    return StrategyRun(cumulativeMs: cumulative / 1_000_000, samples: samples)
}
