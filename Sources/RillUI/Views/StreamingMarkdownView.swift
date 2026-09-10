import SwiftUI
import RillCore
import RillAnalytics

/// Renders a live, streaming ``MarkdownSource`` as its text arrives.
///
/// `StreamingMarkdownView` observes a ``MarkdownSource`` and renders its
/// ``MarkdownSource/document`` through a ``DocumentView``. As the host feeds the
/// source deltas (``MarkdownSource/append(_:)``) or snapshots
/// (``MarkdownSource/setSnapshot(_:)``), the source republishes its document and
/// SwiftUI re-evaluates only this view's body — and within it, only the live tail
/// block, because committed blocks are `Equatable`-gated by ``Block/id``.
///
/// Render telemetry is owned solely by ``MarkdownSource``: it emits exactly one
/// ``RenderMetrics`` per update, with correct skip accounting computed against
/// the previous document. This view deliberately does **not** emit its own
/// `RenderMetrics` from `body` — doing so produced a second, conflicting
/// `didRender` per update (all-rendered/none-skipped) and measured only the time
/// to *construct* a `DocumentView`, not its actual SwiftUI render, and `body`
/// may be evaluated arbitrarily often. The injected ``analytics`` sink is still
/// threaded to the underlying ``DocumentView`` so inline/block interactions
/// (link, citation, copy) are reported.
public struct StreamingMarkdownView: View {

    /// The observed streaming source providing the document to render.
    private var source: MarkdownSource

    /// The visual theme threaded to the underlying ``DocumentView``.
    private let theme: RillTheme

    /// The behavioural configuration threaded to the underlying ``DocumentView``.
    private let config: RenderConfig

    /// The analytics sink forwarded to the underlying ``DocumentView`` for
    /// interaction events (link, citation, copy). Render telemetry is emitted by
    /// ``MarkdownSource``, not by this view.
    private let analytics: any MarkdownAnalytics

    /// Creates a streaming view bound to a source.
    /// - Parameters:
    ///   - source: The ``MarkdownSource`` whose document is rendered live.
    ///   - theme: The visual theme. Defaults to ``RillTheme/default``.
    ///   - config: The behavioural configuration. Defaults to
    ///     ``RenderConfig/default``.
    ///   - analytics: The analytics sink for interaction events (link, citation,
    ///     copy), forwarded to the rendered content. Render telemetry comes from
    ///     the ``MarkdownSource``. Defaults to ``NoopAnalytics``.
    public init(
        _ source: MarkdownSource,
        theme: RillTheme = .default,
        config: RenderConfig = .default,
        analytics: any MarkdownAnalytics = NoopAnalytics()
    ) {
        self.source = source
        self.theme = theme
        self.config = config
        self.analytics = analytics
    }

    /// Renders the source's current ``Document``. Only the live tail re-evaluates
    /// as the stream grows; committed blocks are `Equatable`-gated by
    /// ``Block/id``. Render telemetry is emitted by ``MarkdownSource``, not here.
    public var body: some View {
        DocumentView(
            source.document,
            theme: theme,
            config: config,
            analytics: analytics
        )
    }
}
