import RillAnalytics
import Foundation

/// The incremental, stable-prefix streaming Markdown parser — Rill's headline
/// engine.
///
/// `IncrementalParser` turns a stream of Markdown text (full snapshots or
/// append-deltas) into a continuously-updated ``Document`` while doing work
/// proportional to the *dirty tail*, not the whole buffer. It maintains a growing
/// UTF-8 buffer and a ``commitIndex``: the byte offset past the last
/// definitively-closed block. Everything before ``commitIndex`` is frozen as
/// memoized, fully-resolved blocks keyed by ``NodeID`` — identical bytes reuse the
/// exact same ``Block`` value, so SwiftUI diffing stays cheap. Only the open tail
/// after ``commitIndex`` is re-lexed and re-resolved on each delta.
///
/// The engine satisfies the streaming-equivalence invariant: for any input and
/// any chunking, the final ``document`` equals the one-shot
/// `InlineParser.resolveInlines(in: BlockLexer.lex(...))` result.
///
/// On each parse pass it fires ``onUpdate`` with the new document and emits
/// ``ParseMetrics`` to its analytics sink. The parser is a `final class` holding
/// mutable buffer state; it is not safe to share across threads without external
/// isolation.
public final class IncrementalParser: MarkdownStreamConsumer {

    // MARK: Public surface

    /// The current parsed document: committed (frozen) blocks followed by the
    /// freshly-rebuilt open tail. Updated on every ``consume(snapshot:)`` /
    /// ``consume(delta:at:)`` call.
    public private(set) var document: Document

    /// A callback fired with the new ``document`` after every parse pass.
    public var onUpdate: ((Document) -> Void)?

    // MARK: Configuration

    private let config: ParseConfig
    private let analytics: any MarkdownAnalytics

    // MARK: Mutable state

    /// The growing UTF-8 buffer of all text consumed so far.
    private var buffer: [UInt8] = []

    /// Byte offset past the last definitively-closed block. Bytes `< commitIndex`
    /// are frozen in ``committedBlocks`` and never re-lexed. Exposed `internal`
    /// (settable only within the parser) so the test suite can assert commit
    /// discipline via `@testable import`.
    private(set) var commitIndex: Int = 0

    /// The frozen, fully-resolved blocks for bytes `[0, commitIndex)`.
    private var committedBlocks: [Block] = []

    /// Memoized resolved blocks keyed by the content-derived ``NodeID`` of the
    /// raw lexed block, so identical committed bytes reuse the exact same value
    /// (and skip re-running the inline parser).
    private var memo: [NodeID: Block] = [:]

    // MARK: Init

    /// Creates an incremental parser.
    /// - Parameters:
    ///   - config: The parse configuration (inline-extension toggles). Defaults
    ///     to ``ParseConfig/default``.
    ///   - analytics: The telemetry sink to receive ``ParseMetrics`` on each pass.
    ///     Defaults to ``NoopAnalytics``.
    public init(config: ParseConfig = .default, analytics: any MarkdownAnalytics = NoopAnalytics()) {
        self.config = config
        self.analytics = analytics
        self.document = Document(blocks: [])
    }

    // MARK: MarkdownStreamConsumer

    /// Replaces the buffer with a full snapshot of the text so far and reparses
    /// from the first byte that differs from the previous snapshot.
    ///
    /// Only the changed suffix is re-lexed, so re-emitting a growing snapshot is
    /// O(dirty tail) per call rather than O(buffer).
    public func consume(snapshot: String) {
        let incoming = Array(snapshot.utf8)
        let changedAt = Self.commonPrefixLength(buffer, incoming)
        buffer = incoming
        parse(dirtyStart: changedAt)
    }

    /// Truncates the buffer to `offset`, appends the delta's bytes, and reparses
    /// from the first changed byte.
    ///
    /// This matches a typical append-delta wire format and handles offset-based
    /// re-emits idempotently: replaying the same `(delta, offset)` pair leaves the
    /// document unchanged.
    /// - Parameters:
    ///   - delta: The new text to append at `offset`.
    ///   - offset: The byte offset to truncate to before appending; clamped to the
    ///     current buffer length.
    public func consume(delta: String, at offset: Int) {
        let clamped = max(0, min(offset, buffer.count))
        // Truncate to the offset, then append the delta's bytes.
        var next = Array(buffer[0..<clamped])
        next.append(contentsOf: delta.utf8)
        let changedAt = Self.commonPrefixLength(buffer, next)
        buffer = next
        parse(dirtyStart: changedAt)
    }

    // MARK: Parse pass

    /// Re-lexes from the dirty point, advances the commit boundary past newly
    /// closed blocks (memoizing them), rebuilds the open tail fresh, publishes the
    /// document, and emits metrics.
    ///
    /// - Parameter dirtyStart: The first byte index whose value changed since the
    ///   previous pass. For append-only streaming this is the old buffer length,
    ///   which is `>= commitIndex`, so only the tail is touched.
    private func parse(dirtyStart: Int) {
        let clock = ContinuousClock()
        let start = clock.now

        // If the change landed before the committed prefix, that frozen prefix is
        // no longer valid. Roll the commit boundary back to the dirty point and
        // drop any committed blocks at or after it, then recommit from there.
        if dirtyStart < commitIndex {
            rollBack(to: dirtyStart)
        }

        let reLexStart = commitIndex
        let dirtyTailBytes = buffer.count - reLexStart

        // 1. Find the new commit boundary within the dirty region. The boundary is
        //    expressed in the buffer's own absolute index space.
        let tailSlice = buffer[reLexStart..<buffer.count]
        let newBoundary = CommitBoundary.lastClosedIndex(in: tailSlice)

        var blocksCommitted = 0
        // Every block already in the committed prefix is reused unchanged from a
        // prior pass — that is the stable-prefix win this metric records.
        let blocksReused = committedBlocks.count

        // 2. Commit the newly-closed region [commitIndex, newBoundary). Each
        //    closed block is memoized by its content-derived NodeID so identical
        //    bytes resolve their inlines exactly once across the parser's life.
        if newBoundary > commitIndex {
            let closedSlice = buffer[commitIndex..<newBoundary]
            let rawClosed = BlockLexer.lex(closedSlice)
            for raw in rawClosed {
                let key = raw.id
                let block: Block
                if let cached = memo[key] {
                    block = cached
                } else {
                    let resolved = InlineParser.resolveInlines(in: [raw], config: config)
                    block = resolved.first ?? raw
                    memo[key] = block
                }
                committedBlocks.append(block)
                blocksCommitted += 1
            }
            commitIndex = newBoundary
        }

        // 3. Rebuild the still-open tail fresh from the (new) commit boundary.
        let openSlice = buffer[commitIndex..<buffer.count]
        let tailBlocks: [Block]
        if openSlice.isEmpty {
            tailBlocks = []
        } else {
            let rawTail = BlockLexer.lex(openSlice)
            tailBlocks = InlineParser.resolveInlines(in: rawTail, config: config)
        }

        // 4. Publish committed + tail.
        document = Document(blocks: committedBlocks + tailBlocks)

        let duration = clock.now - start
        onUpdate?(document)
        analytics.didParse(ParseMetrics(
            duration: duration,
            dirtyTailBytes: dirtyTailBytes,
            totalBytes: buffer.count,
            blocksCommitted: blocksCommitted,
            blocksReused: blocksReused
        ))
    }

    /// Invalidates the committed prefix back to `offset`: re-lexes `[0, offset)`'s
    /// remaining closed blocks is unnecessary because the boundary scan re-runs
    /// from `commitIndex`. To stay correct and simple we drop the entire committed
    /// prefix and let the next pass recommit from the start.
    private func rollBack(to offset: Int) {
        _ = offset
        commitIndex = 0
        committedBlocks = []
        // The memo stays valid: it is keyed by content hash, so unchanged blocks
        // re-encountered during recommit reuse their cached values.
    }

    // MARK: Helpers

    /// Returns the length of the longest common prefix of two byte arrays — the
    /// index of the first differing byte (or the shorter length if one is a
    /// prefix of the other).
    private static func commonPrefixLength(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let n = min(a.count, b.count)
        var i = 0
        while i < n, a[i] == b[i] { i += 1 }
        return i
    }
}
