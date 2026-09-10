import SwiftUI
import RillCore

/// Renders a ``BlockQuote`` with a leading theme-colored bar and recursively
/// rendered nested blocks.
struct QuoteView: View {
    /// The block quote to render.
    let quote: BlockQuote

    /// The shared theme/config/analytics environment (nested blocks reuse it).
    let context: BlockRenderContext

    var body: some View {
        HStack(alignment: .top, spacing: context.theme.metrics.blockPadding) {
            RoundedRectangle(cornerRadius: 2)
                .fill(context.theme.colors.quoteBar)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: context.theme.metrics.paragraphSpacing) {
                ForEach(Array(quote.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block, context: context)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, context.theme.metrics.blockPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The render-independent view model for a quote: its flattened plain text.
    /// Exposed for headless assertions over nested content.
    struct Model {
        /// The quote's nested content flattened to plain text.
        let plainText: String

        /// Builds a quote model from its block, theme, and config.
        init(quote: BlockQuote, theme: RillTheme, config: RenderConfig) {
            self.plainText = Model.flatten(quote.blocks)
        }

        /// Recursively collects the plain text of nested blocks.
        private static func flatten(_ blocks: [Block]) -> String {
            var parts: [String] = []
            for block in blocks {
                switch block {
                case .paragraph(let p):
                    parts.append(BlockInlineText.plainText(p.inlines))
                case .heading(let h):
                    parts.append(BlockInlineText.plainText(h.inlines))
                case .blockQuote(let bq):
                    parts.append(flatten(bq.blocks))
                case .alert(let alert):
                    parts.append(flatten(alert.blocks))
                case .list(let list):
                    for item in list.items { parts.append(flatten(item.blocks)) }
                case .codeBlock(let cb):
                    parts.append(cb.content)
                case .footnoteDefinition(let def):
                    parts.append(flatten(def.blocks))
                case .table, .thematicBreak, .mathBlock, .htmlBlock:
                    break
                }
            }
            return parts.joined(separator: "\n")
        }
    }
}
