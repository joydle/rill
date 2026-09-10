import SwiftUI

/// The live analytics heads-up display overlaid on the streaming demo.
///
/// Reads a ``HUDSnapshot`` (typically the observable `snapshot` of a
/// ``HUDAnalyticsSink``) and shows the headline streaming metrics: parse time in
/// milliseconds, dirty-tail bytes re-lexed, and blocks reused via stable-identity
/// versus rendered/skipped/committed. It is purely presentational.
public struct HUDView: View {

    /// The metrics snapshot to display.
    private let snapshot: HUDSnapshot

    /// Creates a HUD view.
    /// - Parameter snapshot: The metrics to display.
    public init(snapshot: HUDSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live analytics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                metric("parse", String(format: "%.3f ms", snapshot.parseMilliseconds))
                metric("dirty tail", "\(snapshot.dirtyTailBytes) B")
                metric("total", "\(snapshot.totalBytes) B")
            }
            HStack(spacing: 16) {
                metric("reused", "\(snapshot.blocksReused)")
                metric("rendered", "\(snapshot.blocksRendered)")
                metric("skipped", "\(snapshot.blocksSkipped)")
                metric("committed", "\(snapshot.blocksCommitted)")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.secondary.opacity(0.2))
        )
    }

    /// A single labelled metric column.
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .monospacedDigit()
        }
    }
}
