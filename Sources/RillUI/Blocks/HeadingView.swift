import SwiftUI
import RillCore

/// Renders a ``Heading`` block at the theme's per-level font.
///
/// Inline content is laid out through ``RichInlineText`` so any links,
/// citations, or inline math inside a heading render interactively while the
/// text keeps the per-level heading font.
struct HeadingView: View {
    /// The heading to render.
    let heading: Heading

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// Whether this heading is the active streaming tail (and may animate its
    /// newly appended text). Committed headings pass `false`.
    var isActiveTail: Bool = false

    var body: some View {
        let model = Model(heading: heading, theme: context.theme)
        RichInlineText(
            inlines: heading.inlines,
            context: context,
            font: model.font,
            isActiveTail: isActiveTail
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    /// The render-independent view model for a heading: its level, font, and
    /// styled text. Exposed for headless assertions.
    struct Model {
        /// The heading level (1–6).
        let level: Int
        /// The font for this heading level.
        let font: Font
        /// The styled inline text of the heading.
        let text: AttributedString

        /// Builds a heading model from its block and theme.
        init(heading: Heading, theme: RillTheme) {
            self.level = heading.level
            self.font = theme.fonts.heading(level: heading.level)
            self.text = BlockInlineText.attributed(heading.inlines, theme: theme)
        }
    }
}
