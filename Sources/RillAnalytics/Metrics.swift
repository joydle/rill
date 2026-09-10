/// Telemetry emitted once per incremental parse pass.
///
/// These values quantify the dirty-tail re-lex: how much of the buffer was
/// re-examined (``dirtyTailBytes`` of ``totalBytes``), how many blocks were
/// newly committed (``blocksCommitted``), and how many committed blocks were
/// reused unchanged from the previous pass (``blocksReused``). A healthy
/// streaming session shows ``dirtyTailBytes`` staying small relative to
/// ``totalBytes`` and ``blocksReused`` growing, confirming O(tail) parsing.
public struct ParseMetrics: Sendable, Hashable {
    /// Wall-clock time spent in the parse pass.
    public let duration: Duration

    /// Number of bytes re-lexed in this pass (the dirty tail from `commitIndex`).
    public let dirtyTailBytes: Int

    /// Total size of the accumulated UTF-8 buffer at the end of the pass.
    public let totalBytes: Int

    /// Number of blocks newly committed (closed and frozen) in this pass.
    public let blocksCommitted: Int

    /// Number of previously committed blocks reused unchanged via memoization.
    public let blocksReused: Int

    /// Creates a parse-metrics record.
    /// - Parameters:
    ///   - duration: Wall-clock time spent in the parse pass.
    ///   - dirtyTailBytes: Bytes re-lexed in this pass.
    ///   - totalBytes: Total buffer size at the end of the pass.
    ///   - blocksCommitted: Blocks newly committed this pass.
    ///   - blocksReused: Committed blocks reused unchanged this pass.
    public init(
        duration: Duration,
        dirtyTailBytes: Int,
        totalBytes: Int,
        blocksCommitted: Int,
        blocksReused: Int
    ) {
        self.duration = duration
        self.dirtyTailBytes = dirtyTailBytes
        self.totalBytes = totalBytes
        self.blocksCommitted = blocksCommitted
        self.blocksReused = blocksReused
    }
}

/// Telemetry derived once per document update (``MarkdownSource/append(_:)`` or
/// ``MarkdownSource/setSnapshot(_:)``) by diffing the new document against the
/// previous one.
///
/// ``blocksRendered`` plus ``blocksSkipped`` accounts for every block in the
/// document; ``blocksSkipped`` counts blocks whose value is unchanged and whose
/// view SwiftUI can therefore reuse via stable-identity (`Equatable`) gating —
/// the streaming smoothness win. These are structural counts diffed from the
/// document; the view layer does not time its own body (see
/// ``StreamingMarkdownView``), so no wall-clock duration is reported.
public struct RenderMetrics: Sendable, Hashable {
    /// Number of blocks whose value changed and whose view is therefore
    /// (re)evaluated for this update.
    public let blocksRendered: Int

    /// Number of blocks skipped via stable-identity (`Equatable`) gating.
    public let blocksSkipped: Int

    /// Creates a render-metrics record.
    /// - Parameters:
    ///   - blocksRendered: Blocks whose value changed this update.
    ///   - blocksSkipped: Blocks skipped via stable-identity gating.
    public init(
        blocksRendered: Int,
        blocksSkipped: Int
    ) {
        self.blocksRendered = blocksRendered
        self.blocksSkipped = blocksSkipped
    }
}

/// A user interaction with a rendered Markdown element.
///
/// Emitted via ``MarkdownAnalytics/didInteract(_:)`` so hosts can wire taps and
/// copies into their own analytics pipeline.
public enum MarkdownInteraction: Sendable, Hashable {
    /// The user tapped a link. `url` is the link's destination as written.
    case linkTapped(url: String)

    /// The user copied a code block. `language` is the fence's language tag, if any.
    case codeCopied(language: String?)

    /// The user tapped a citation pill. `marker` is the citation marker text
    /// (e.g. `"1"` or `"ref"`); `index` is its resolved position, if known.
    case citationTapped(marker: String, index: Int?)

    /// The user copied a table. `rows` and `columns` describe its dimensions.
    case tableCopied(rows: Int, columns: Int)

    /// The user tapped an image. `url` is the image source as written.
    case imageTapped(url: String)
}
