import Foundation

/// Splits a finished Markdown string into fixed-size chunks so the demo can
/// replay it token-by-token, the way an LLM response arrives over the wire.
///
/// The simulator is a pure value type: ``chunks()`` deterministically slices the
/// text into pieces of ``chunkSize`` characters (the last chunk holds the
/// remainder), and the chunks always reassemble to the original string. The
/// ``delay`` is metadata describing how long the demo should pause between
/// chunks; the simulator itself performs no timing, which keeps it testable
/// headlessly.
public struct StreamingSimulator: Sendable, Equatable {

    /// The full Markdown text to replay.
    public var text: String

    /// The number of `Character`s emitted per chunk. Values below `1` are
    /// clamped to `1` so chunking always makes progress.
    public var chunkSize: Int

    /// How long the demo should wait between emitting chunks. Not used by
    /// ``chunks()``; it is timing metadata for the playback loop.
    public var delay: Duration

    /// Creates a streaming simulator.
    /// - Parameters:
    ///   - text: The full Markdown text to replay.
    ///   - chunkSize: Characters per chunk (clamped to at least `1`).
    ///   - delay: The inter-chunk delay used by the playback loop.
    public init(text: String, chunkSize: Int, delay: Duration) {
        self.text = text
        self.chunkSize = chunkSize
        self.delay = delay
    }

    /// The effective chunk size, never below `1`.
    public var effectiveChunkSize: Int { max(1, chunkSize) }

    /// Slices ``text`` into ordered chunks of ``effectiveChunkSize`` characters.
    ///
    /// - Returns: The chunks in emission order. Joining them reproduces ``text``
    ///   exactly. An empty ``text`` yields an empty array.
    public func chunks() -> [String] {
        guard !text.isEmpty else { return [] }
        let size = effectiveChunkSize
        var result: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[index..<end]))
            index = end
        }
        return result
    }
}
