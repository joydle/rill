import Foundation
import Observation
import RillAnalytics

/// A snapshot of the live metrics shown in the demo's analytics HUD.
///
/// Pure value type so views can diff it cheaply. Captures the latest parse and
/// render telemetry (parse time, dirty-tail bytes, and block reuse/render/skip
/// counts).
public struct HUDSnapshot: Sendable, Equatable {
    /// Duration of the most recent parse pass, in milliseconds.
    public var parseMilliseconds: Double = 0
    /// Bytes re-lexed in the most recent parse pass (the dirty tail).
    public var dirtyTailBytes: Int = 0
    /// Total accumulated UTF-8 buffer size after the most recent parse.
    public var totalBytes: Int = 0
    /// Committed blocks reused unchanged in the most recent parse.
    public var blocksReused: Int = 0
    /// Blocks newly committed in the most recent parse.
    public var blocksCommitted: Int = 0
    /// Blocks drawn in the most recent render.
    public var blocksRendered: Int = 0
    /// Blocks skipped via stable-identity gating in the most recent render.
    public var blocksSkipped: Int = 0
    /// Count of parse passes observed since the last ``HUDAnalyticsSink/reset()``.
    public var parsePasses: Int = 0

    /// Creates an empty snapshot with all metrics zeroed.
    public init() {}
}

/// An `@Observable`, `MarkdownAnalytics` sink that feeds the demo's live HUD.
///
/// It records the latest ``ParseMetrics`` and ``RenderMetrics`` into an
/// observable ``snapshot`` (parse milliseconds, dirty-tail bytes, blocks reused/committed,
/// rendered/skipped) that the HUD view reads directly. Because Rill drives the
/// parser synchronously from the `@MainActor`-isolated `MarkdownSource`, both
/// callbacks arrive on the main actor; the `nonisolated` protocol requirements
/// re-enter the main actor to mutate observable state.
@MainActor
@Observable
public final class HUDAnalyticsSink: MarkdownAnalytics {

    /// A process-wide shared sink so the demo's source and HUD observe the same
    /// metrics instance.
    public static let shared = HUDAnalyticsSink()

    /// The current metrics shown in the HUD.
    public private(set) var snapshot = HUDSnapshot()

    /// Creates a HUD sink with an empty snapshot.
    public init() {}

    /// Clears all accumulated metrics back to zero.
    public func reset() {
        snapshot = HUDSnapshot()
    }

    nonisolated public func didParse(_ metrics: ParseMetrics) {
        MainActor.assumeIsolated {
            var next = snapshot
            next.parseMilliseconds = Self.milliseconds(metrics.duration)
            next.dirtyTailBytes = metrics.dirtyTailBytes
            next.totalBytes = metrics.totalBytes
            next.blocksReused = metrics.blocksReused
            next.blocksCommitted = metrics.blocksCommitted
            next.parsePasses += 1
            snapshot = next
        }
    }

    nonisolated public func didRender(_ metrics: RenderMetrics) {
        MainActor.assumeIsolated {
            var next = snapshot
            next.blocksRendered = metrics.blocksRendered
            next.blocksSkipped = metrics.blocksSkipped
            snapshot = next
        }
    }

    nonisolated public func didInteract(_ interaction: MarkdownInteraction) {
        // Interactions are not surfaced in the HUD; ignored.
    }

    /// Converts a `Duration` to milliseconds as a `Double`.
    static func milliseconds(_ duration: Duration) -> Double {
        let comps = duration.components
        return Double(comps.seconds) * 1_000
            + Double(comps.attoseconds) / 1_000_000_000_000_000
    }
}
