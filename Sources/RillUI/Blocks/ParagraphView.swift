import SwiftUI
import RillCore

/// Renders a ``Paragraph`` block as flowing inline text.
///
/// Inline content is laid out through ``RichInlineText`` so links, citations,
/// inline math, and inline images render interactively (routing through the
/// host's ``RenderConfig`` hooks) rather than as flattened text.
struct ParagraphView: View {
    /// The paragraph to render.
    let paragraph: Paragraph

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// Whether this paragraph is the active streaming tail (and may animate its
    /// newly appended text). Committed paragraphs pass `false`.
    var isActiveTail: Bool = false

    var body: some View {
        RichInlineText(inlines: paragraph.inlines, context: context, isActiveTail: isActiveTail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The render-independent view model for a paragraph: its styled inline
    /// text and whether its appended text animates. Exposed for headless
    /// assertions.
    struct Model {
        /// The styled inline content of the paragraph.
        let text: AttributedString

        /// Whether this paragraph would animate its appended text: only the
        /// active streaming tail animates, and only when the configured
        /// ``RenderConfig/appendAnimation`` is not
        /// ``RenderConfig/AppendAnimation/none``. Committed blocks are always
        /// `false`.
        let animatesAppend: Bool

        /// Builds a paragraph model from its block, theme, and config.
        /// - Parameters:
        ///   - paragraph: The paragraph block.
        ///   - theme: The visual theme.
        ///   - config: The render configuration.
        ///   - isActiveTail: Whether this paragraph is the live streaming tail.
        ///     Defaults to `false` (a committed block).
        init(paragraph: Paragraph, theme: RillTheme, config: RenderConfig, isActiveTail: Bool = false) {
            self.text = BlockInlineText.attributed(paragraph.inlines, theme: theme)
            self.animatesAppend = isActiveTail && config.appendAnimation != .none
        }
    }
}
