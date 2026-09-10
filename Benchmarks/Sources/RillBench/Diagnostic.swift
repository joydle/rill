import Foundation
import RillCore
import RillAnalytics

/// A sink that records every ParseMetrics for diagnosis.
final class RecordingAnalytics: MarkdownAnalytics, @unchecked Sendable {
    var metrics: [ParseMetrics] = []
    func didParse(_ m: ParseMetrics) { metrics.append(m) }
    func didRender(_ m: RenderMetrics) {}
    func didInteract(_ e: MarkdownInteraction) {}
}

/// Prints per-delta dirty-tail bytes vs total bytes for a streamed doc, proving
/// the commit boundary advances: the dirty tail stays bounded (O(tail)) while the
/// document grows, and `blocksReused` accumulates.
func runDiagnostic() {
    let md = SyntheticMarkdown.generate(targetBytes: 16384)
    let bytes = Array(md.utf8)
    let chunks = chunkize(bytes, chunkSize: 256)
    let rec = RecordingAnalytics()
    let parser = IncrementalParser(analytics: rec)
    var offset = 0
    for chunk in chunks {
        parser.consume(delta: String(decoding: chunk, as: UTF8.self), at: offset)
        offset += chunk.count
    }
    print("DIAGNOSTIC: per-delta dirtyTailBytes vs totalBytes (16KB doc, 256B chunks)")
    print("  (dirty tail stays bounded while total grows => O(tail) incremental parse)")
    for (i, m) in rec.metrics.enumerated() {
        if i % 8 == 0 || i == rec.metrics.count - 1 {
            print(String(format: "  delta %3d: total=%6d  dirtyTail=%6d  committed=%3d  reused=%4d  %.4f ms",
                         i, m.totalBytes, m.dirtyTailBytes, m.blocksCommitted, m.blocksReused,
                         m.duration.nanoseconds / 1_000_000))
        }
    }
}
