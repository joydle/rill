import SwiftUI
import RillCore
import struct RillCore.List

/// Renders a ``List`` block — ordered or unordered, arbitrarily nested, with GFM
/// task-list checkboxes.
///
/// Each item renders *all* of its blocks through ``BlockView`` (not just its
/// leading paragraph), so multi-block items — a second paragraph, a nested code
/// block, a blockquote, a table, a sub-list — keep their full content. Inter-item
/// spacing honors ``RillCore/List/isTight``: tight lists pack rows closely while
/// loose lists use the full paragraph spacing.
struct ListView: View {
    /// The list to render.
    let list: List

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    var body: some View {
        let spacing = list.isTight
            ? context.theme.metrics.paragraphSpacing / 2
            : context.theme.metrics.paragraphSpacing
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                ListItemRowView(
                    marker: marker(forItemAt: index),
                    checkbox: item.checkbox,
                    blocks: item.blocks,
                    context: context
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The leading marker text for the item at `index` (used only when the item
    /// has no task checkbox standing in for it).
    private func marker(forItemAt index: Int) -> String {
        list.isOrdered ? "\(list.start + index)." : "•"
    }

    /// The render-independent view model for a list: a flattened, indented row
    /// sequence. Exposed for headless assertions.
    struct Model {
        /// A single rendered list line.
        struct Row {
            /// The nesting depth (0 for the outermost list).
            let depth: Int
            /// The leading marker (`"1."`, `"•"`, …); empty when a checkbox
            /// stands in for the marker.
            let marker: String
            /// The GFM task-list checkbox state, or `nil` for a plain item.
            let checkbox: Bool?
            /// The styled inline text of the item's primary paragraph.
            let text: AttributedString

            /// Builds the SwiftUI row, indented per depth.
            @ViewBuilder
            func view(theme: RillTheme) -> some View {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let checkbox {
                        Image(systemName: checkbox ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checkbox ? theme.colors.link : theme.colors.textSecondary)
                            .accessibilityLabel(checkbox ? "checked" : "unchecked")
                    } else {
                        Text(marker)
                            .font(theme.fonts.body)
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(minWidth: 16, alignment: .trailing)
                    }
                    Text(text)
                        .font(theme.fonts.body)
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CGFloat(depth) * theme.metrics.listIndent)
            }
        }

        /// The flattened rows of the list, in document order.
        let rows: [Row]

        /// Builds a list model from its block, theme, and config.
        init(list: List, theme: RillTheme, config: RenderConfig) {
            var rows: [Row] = []
            Model.flatten(list, depth: 0, theme: theme, into: &rows)
            self.rows = rows
        }

        /// Recursively flattens a list (and its nested lists) into indented rows.
        private static func flatten(
            _ list: List,
            depth: Int,
            theme: RillTheme,
            into rows: inout [Row]
        ) {
            var ordinal = list.start
            for item in list.items {
                let marker: String
                if list.isOrdered {
                    marker = "\(ordinal)."
                    ordinal += 1
                } else {
                    marker = item.checkbox == nil ? "•" : ""
                }

                // The item's leading paragraph becomes the row's text; nested
                // blocks (sub-lists, etc.) are flattened after it.
                var text = AttributedString()
                var nestedLists: [List] = []
                for block in item.blocks {
                    switch block {
                    case .paragraph(let p):
                        if text.characters.isEmpty {
                            text = BlockInlineText.attributed(p.inlines, theme: theme)
                        }
                    case .list(let sublist):
                        nestedLists.append(sublist)
                    case .heading(let h):
                        if text.characters.isEmpty {
                            text = BlockInlineText.attributed(h.inlines, theme: theme)
                        }
                    case .blockQuote, .alert, .codeBlock, .table, .thematicBreak,
                         .mathBlock, .htmlBlock, .footnoteDefinition:
                        break
                    }
                }

                rows.append(Row(depth: depth, marker: marker,
                                checkbox: item.checkbox, text: text))

                for sublist in nestedLists {
                    flatten(sublist, depth: depth + 1, theme: theme, into: &rows)
                }
            }
        }
    }
}

/// Renders a single list item: its marker (or task checkbox) beside the full
/// stack of the item's blocks, each rendered through ``BlockView`` so no content
/// is dropped.
private struct ListItemRowView: View {
    /// The leading ordinal/bullet marker; shown only when `checkbox` is `nil`.
    let marker: String
    /// The GFM task-list checkbox state, or `nil` for a plain item.
    let checkbox: Bool?
    /// Every block belonging to the item, in document order.
    let blocks: [Block]
    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let checkbox {
                Image(systemName: checkbox ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checkbox ? context.theme.colors.link : context.theme.colors.textSecondary)
                    .accessibilityLabel(checkbox ? "checked" : "unchecked")
            } else {
                Text(marker)
                    .font(context.theme.fonts.body)
                    .foregroundStyle(context.theme.colors.textSecondary)
                    .frame(minWidth: 16, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: context.theme.metrics.paragraphSpacing / 2) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    // A nested list gets a uniform, controlled per-level indent of
                    // `listIndent` so the rendered nesting matches the headless
                    // ``ListView/Model`` (depth × listIndent) instead of drifting
                    // with the parent marker's width.
                    if case .list = block {
                        BlockView(block: block, context: context)
                            .padding(.leading, context.theme.metrics.listIndent)
                    } else {
                        BlockView(block: block, context: context)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
