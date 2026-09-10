import SwiftUI
import RillCore
import RillAnalytics

/// Renders a pre-parsed ``Document`` as a vertical stack of block views.
///
/// `DocumentView` is the static, non-streaming entry point: given a parsed
/// document, a ``RillTheme``, a ``RenderConfig``, and a ``MarkdownAnalytics``
/// sink, it lays out each block top-to-bottom. Every block is wrapped in an
/// ``EquatableBlockView`` and gated with `.equatable()`, so blocks whose
/// ``Block/id`` is unchanged across document updates skip body evaluation — the
/// committed prefix of a streamed answer never re-renders, only the live tail
/// does. `StreamingMarkdownView` feeds this view from an incremental
/// parser.
public struct DocumentView: View {
    /// The document to render.
    private let document: Document

    /// The shared theme/config/analytics environment threaded to every block.
    private let context: BlockRenderContext

    /// Creates a document view.
    /// - Parameters:
    ///   - document: The parsed document to render.
    ///   - theme: The visual theme. Defaults to ``RillTheme/default``.
    ///   - config: The behavioural configuration. Defaults to
    ///     ``RenderConfig/default``.
    ///   - analytics: The analytics sink for interaction and render events.
    ///     Defaults to ``NoopAnalytics``.
    public init(
        _ document: Document,
        theme: RillTheme = .default,
        config: RenderConfig = .default,
        analytics: any MarkdownAnalytics = NoopAnalytics()
    ) {
        self.document = document
        self.context = BlockRenderContext(
            theme: theme,
            config: config,
            analytics: analytics,
            footnotes: FootnoteRegistry(document: document)
        )
    }

    /// Lays the document's blocks out top-to-bottom, each wrapped in an
    /// ``EquatableBlockView`` so unchanged blocks skip re-rendering.
    public var body: some View {
        VStack(alignment: .leading, spacing: context.theme.metrics.paragraphSpacing) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { index, block in
                EquatableBlockView(
                    block: block,
                    context: context,
                    isActiveTail: TailAnimationPlan.animatesBlock(
                        at: index, count: document.blocks.count, config: context.config
                    )
                )
                .equatable()
            }
            if !context.footnotes.isEmpty {
                FootnotesSectionView(context: context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
