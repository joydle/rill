import SwiftUI
import RillCore
import RillAnalytics

/// The shared, value-type rendering environment threaded through every block
/// view.
///
/// `BlockRenderContext` bundles the visual ``RillTheme``, the behavioural
/// ``RenderConfig``, and the ``MarkdownAnalytics`` sink so individual block
/// views (``HeadingView``, ``CodeBlockView``, ``TableView``, …) can style
/// themselves, resolve host hooks, and report interactions without each taking a
/// long initializer. It is cheap to copy and carries no rendering identity of
/// its own, so it never forces a committed block to re-render.
public struct BlockRenderContext: Sendable {
    /// The visual theme applied to rendered blocks.
    public var theme: RillTheme

    /// The behavioural configuration (link/citation/image hooks, animation).
    public var config: RenderConfig

    /// The analytics sink that receives interaction events (code/table copies,
    /// link and citation taps).
    public var analytics: any MarkdownAnalytics

    /// The document's footnote index, used to render footnote references as
    /// numbered superscript markers. Empty unless the document defines footnotes.
    public var footnotes: FootnoteRegistry

    /// Creates a block render context.
    /// - Parameters:
    ///   - theme: The visual theme.
    ///   - config: The behavioural configuration.
    ///   - analytics: The analytics sink for interaction events.
    ///   - footnotes: The document footnote index. Defaults to
    ///     ``FootnoteRegistry/empty`` so existing callers need not supply one.
    public init(
        theme: RillTheme,
        config: RenderConfig,
        analytics: any MarkdownAnalytics,
        footnotes: FootnoteRegistry = .empty
    ) {
        self.theme = theme
        self.config = config
        self.analytics = analytics
        self.footnotes = footnotes
    }
}
