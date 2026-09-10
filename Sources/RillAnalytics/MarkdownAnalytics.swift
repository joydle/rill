/// A sink that receives telemetry about Rill's parsing, rendering, and user
/// interaction with rendered Markdown.
///
/// Rill emits three kinds of signals:
/// - ``didParse(_:)`` once per incremental parse pass, carrying ``ParseMetrics``
///   describing how much work the dirty-tail re-lex performed.
/// - ``didRender(_:)`` once per document update, carrying ``RenderMetrics``
///   describing how many blocks changed (and are re-rendered) versus how many
///   were skipped by stable-identity gating.
/// - ``didInteract(_:)`` whenever the user taps a link, copies code or a table,
///   taps a citation, or taps an image.
///
/// Conformers must be `Sendable`: parse callbacks arrive on the parser's
/// isolation while render and interaction callbacks arrive on the main actor.
/// Implementations must be cheap and non-throwing; a slow sink will stall
/// streaming. The default sink is ``NoopAnalytics``.
public protocol MarkdownAnalytics: Sendable {
    /// Called once per incremental parse pass with metrics about the work done.
    func didParse(_ metrics: ParseMetrics)

    /// Called once per document update with metrics about how many blocks
    /// changed versus were skipped via stable-identity gating.
    func didRender(_ metrics: RenderMetrics)

    /// Called when the user interacts with a rendered element.
    func didInteract(_ interaction: MarkdownInteraction)
}
