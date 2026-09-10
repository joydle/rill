import Foundation
import Observation
import RillCore
import RillAnalytics

/// An observable streaming source that drives ``StreamingMarkdownView``.
///
/// `MarkdownSource` wraps an ``IncrementalParser`` and republishes its
/// ``document`` as `@Observable` state so SwiftUI re-renders as text streams in.
/// Hosts feed it either append-deltas (``append(_:)`` — the token-by-token wire
/// format of an LLM response) or full snapshots (``setSnapshot(_:)``). Because it
/// is backed by the incremental engine, the published ``document`` after any
/// chunking is byte-identical to a one-shot parse of the same text — the
/// streaming-equivalence invariant.
///
/// On every update the source computes a render plan against the previous
/// document and reports ``RenderMetrics`` to its injected ``MarkdownAnalytics``
/// sink, so the committed prefix shows up as *skipped* and only the live tail as
/// *rendered*. This makes the tail-only re-render behaviour observable headlessly,
/// independent of SwiftUI body evaluation.
///
/// The source is `@MainActor`-isolated: it is created and fed from the UI layer,
/// and its `@Observable` mutations must land on the main actor for SwiftUI.
@MainActor
@Observable
public final class MarkdownSource {

    /// The current parsed document, updated on every ``append(_:)`` /
    /// ``setSnapshot(_:)`` call. SwiftUI views observing this property re-render
    /// when it changes; only blocks whose ``Block/id`` changed are redrawn.
    public private(set) var document: Document

    /// The wrapped incremental engine. Not observed directly; the source mirrors
    /// its ``IncrementalParser/document`` into ``document`` on each pass.
    @ObservationIgnored
    private let parser: IncrementalParser

    /// The analytics sink that receives ``RenderMetrics`` describing how many
    /// blocks were redrawn versus skipped on each update.
    @ObservationIgnored
    private let analytics: any MarkdownAnalytics

    /// The total UTF-8 length fed so far, used to compute append offsets for the
    /// parser's delta entry point.
    @ObservationIgnored
    private var bufferLength: Int = 0

    /// Creates a streaming source.
    /// - Parameters:
    ///   - config: The parse configuration forwarded to the incremental engine.
    ///     Defaults to ``ParseConfig/default``.
    ///   - analytics: The telemetry sink receiving ``ParseMetrics`` (from the
    ///     parser) and ``RenderMetrics`` (from this source). Defaults to
    ///     ``NoopAnalytics``.
    public init(
        config: ParseConfig = .default,
        analytics: any MarkdownAnalytics = NoopAnalytics()
    ) {
        self.analytics = analytics
        self.parser = IncrementalParser(config: config, analytics: analytics)
        self.document = parser.document
    }

    /// Appends a delta of new text to the end of the stream.
    ///
    /// This is the token-by-token entry point: each streamed fragment is appended
    /// to the growing buffer and the dirty tail is re-parsed in time proportional
    /// to its length, not the whole document.
    /// - Parameter text: The newly arrived text to append.
    public func append(_ text: String) {
        parser.consume(delta: text, at: bufferLength)
        bufferLength += text.utf8.count
        publish()
    }

    /// Replaces the entire stream with a full snapshot of the text so far.
    ///
    /// Use this when the host holds the complete accumulated string rather than
    /// per-token deltas. The engine still only re-parses from the first byte that
    /// differs from the previous snapshot.
    /// - Parameter text: The full Markdown text so far.
    public func setSnapshot(_ text: String) {
        parser.consume(snapshot: text)
        bufferLength = text.utf8.count
        publish()
    }

    /// Mirrors the parser's new document into the observable property and reports
    /// render metrics for the transition.
    private func publish() {
        let previous = document
        let next = parser.document
        let metrics = DocumentRenderPlan.metrics(previous: previous, current: next)
        document = next
        analytics.didRender(metrics)
    }
}
