import SwiftUI
import RillCore

/// Renders a GitHub-style ``Alert`` callout: an icon and title row over a tinted
/// left border and faint background, with the alert's nested blocks beneath.
///
/// The tint comes from ``RillTheme/AlertColors`` keyed by the alert's
/// ``AlertKind``; the icon is an SF Symbol chosen per kind. Nested blocks render
/// recursively through ``BlockView`` so a callout can contain paragraphs, lists,
/// code, and so on.
struct AlertView: View {
    /// The alert to render.
    let alert: MarkdownAlert

    /// The shared theme/config/analytics environment (nested blocks reuse it).
    let context: BlockRenderContext

    var body: some View {
        let tint = context.theme.colors.alerts.tint(for: alert.kind)
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: context.theme.metrics.paragraphSpacing) {
                HStack(spacing: 6) {
                    Image(systemName: Self.iconName(alert.kind))
                        .foregroundStyle(tint)
                    Text(alert.kind.displayTitle)
                        .font(.headline)
                        .foregroundStyle(tint)
                }
                ForEach(Array(alert.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block, context: context)
                }
            }
            .padding(context.theme.metrics.blockPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: context.theme.metrics.cornerRadius)
                .fill(tint.opacity(0.08))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The SF Symbol name for an alert kind's leading icon.
    nonisolated static func iconName(_ kind: AlertKind) -> String {
        switch kind {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.bubble.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "exclamationmark.octagon.fill"
        }
    }

    /// The render-independent view model for an alert: its title, icon, and
    /// flattened plain text. Exposed for headless assertions.
    struct Model {
        /// The callout title (`"Note"`, `"Warning"`, …).
        let title: String
        /// The SF Symbol name of the leading icon.
        let iconName: String
        /// The callout's nested content flattened to plain text.
        let plainText: String

        /// Builds an alert model from its block and theme.
        init(alert: MarkdownAlert, theme: RillTheme) {
            self.title = alert.kind.displayTitle
            self.iconName = AlertView.iconName(alert.kind)
            self.plainText = Model.flatten(alert.blocks)
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
                case .alert(let a):
                    parts.append(flatten(a.blocks))
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
