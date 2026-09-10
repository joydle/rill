import Foundation
import os

/// The default analytics sink: it discards every signal.
///
/// Use ``NoopAnalytics`` when telemetry is not needed. Every method is a no-op,
/// so it imposes no overhead and never crashes regardless of input.
public struct NoopAnalytics: MarkdownAnalytics {
    /// Creates a no-op analytics sink.
    public init() {}

    /// Discards the parse metrics.
    public func didParse(_ metrics: ParseMetrics) {}
    /// Discards the render metrics.
    public func didRender(_ metrics: RenderMetrics) {}
    /// Discards the interaction event.
    public func didInteract(_ interaction: MarkdownInteraction) {}
}

/// An analytics sink that emits `os.signpost` events so parse and render passes
/// appear in Instruments, and logs interactions.
///
/// Each ``didParse(_:)`` and ``didRender(_:)`` call emits a single signpost
/// *event* annotated with the reported metric — including the measured
/// ``ParseMetrics/duration`` / ``RenderMetrics/duration`` (in nanoseconds) as
/// event metadata — plus a log line carrying the metric counts. An event (not an
/// interval) is used deliberately: `OSSignposter` cannot back-date a
/// `beginInterval` to `now - duration`, so a begin/end pair emitted back-to-back
/// would always show a ~0-width region that does *not* reflect the metric.
/// Carrying the duration as metadata reports it faithfully. Interactions are
/// logged. All output is fire-and-forget; the sink never throws and never blocks
/// meaningfully.
public struct OSLogAnalytics: MarkdownAnalytics {
    private let signposter: OSSignposter
    private let log: Logger

    /// Creates an `os.signpost` analytics sink.
    /// - Parameters:
    ///   - subsystem: The logging subsystem (reverse-DNS recommended).
    ///   - category: The logging category used for both signposts and logs.
    public init(
        subsystem: String = "com.rill.analytics",
        category: String = "Markdown"
    ) {
        let osLog = OSLog(subsystem: subsystem, category: category)
        self.signposter = OSSignposter(logHandle: osLog)
        self.log = Logger(subsystem: subsystem, category: category)
    }

    /// Emits a `parse` signpost event carrying the measured duration and logs the
    /// parse-pass metric counts.
    public func didParse(_ metrics: ParseMetrics) {
        let nanos = Self.nanoseconds(metrics.duration)
        signposter.emitEvent(
            "parse",
            "duration_ns=\(nanos, privacy: .public) dirtyTailBytes=\(metrics.dirtyTailBytes, privacy: .public)"
        )
        log.debug(
            """
            rill.parse durationNs=\(nanos, privacy: .public) \
            dirtyTailBytes=\(metrics.dirtyTailBytes, privacy: .public) \
            totalBytes=\(metrics.totalBytes, privacy: .public) \
            blocksCommitted=\(metrics.blocksCommitted, privacy: .public) \
            blocksReused=\(metrics.blocksReused, privacy: .public)
            """
        )
    }

    /// Emits a `render` signpost event and logs the per-update block accounting
    /// (how many blocks changed versus were skipped via stable-identity gating).
    public func didRender(_ metrics: RenderMetrics) {
        signposter.emitEvent(
            "render",
            "blocksRendered=\(metrics.blocksRendered, privacy: .public) blocksSkipped=\(metrics.blocksSkipped, privacy: .public)"
        )
        log.debug(
            """
            rill.render blocksRendered=\(metrics.blocksRendered, privacy: .public) \
            blocksSkipped=\(metrics.blocksSkipped, privacy: .public)
            """
        )
    }

    /// Converts a `Duration` to whole nanoseconds for signpost/log metadata.
    private static func nanoseconds(_ duration: Duration) -> Int64 {
        let c = duration.components
        return c.seconds * 1_000_000_000 + c.attoseconds / 1_000_000_000
    }

    /// Emits an `interact` signpost event and logs the interaction.
    public func didInteract(_ interaction: MarkdownInteraction) {
        signposter.emitEvent("interact")
        log.debug("rill.interact \(String(describing: interaction), privacy: .public)")
    }
}

/// An analytics sink that fans out every signal to a fixed array of children,
/// in order.
///
/// Use ``MultiplexAnalytics`` to combine several sinks — for example an
/// ``OSLogAnalytics`` for Instruments alongside a host-provided sink. With an
/// empty array it behaves like ``NoopAnalytics``.
public struct MultiplexAnalytics: MarkdownAnalytics {
    private let children: [any MarkdownAnalytics]

    /// Creates a multiplexing sink over the given children.
    /// - Parameter children: The sinks to forward every signal to, in order.
    public init(_ children: [any MarkdownAnalytics]) {
        self.children = children
    }

    /// Forwards the parse metrics to every child sink, in order.
    public func didParse(_ metrics: ParseMetrics) {
        for child in children { child.didParse(metrics) }
    }

    /// Forwards the render metrics to every child sink, in order.
    public func didRender(_ metrics: RenderMetrics) {
        for child in children { child.didRender(metrics) }
    }

    /// Forwards the interaction event to every child sink, in order.
    public func didInteract(_ interaction: MarkdownInteraction) {
        for child in children { child.didInteract(interaction) }
    }
}
