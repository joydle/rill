import SwiftUI
import RillCore
import RillAnalytics
import struct RillCore.Table

/// Renders a GFM ``Table`` using SwiftUI `Grid`, honoring per-column alignment,
/// with a copy action.
///
/// The header row is emphasized; body rows alternate naturally under the theme.
/// Copy serializes the table to tab-separated text and fires
/// ``MarkdownInteraction/tableCopied(rows:columns:)``.
struct TableView: View {
    /// The table to render.
    let table: Table

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    var body: some View {
        let model = Model(table: table, theme: context.theme, config: context.config)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Button(action: performCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(context.theme.colors.textSecondary)
                .accessibilityLabel("Copy table")
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .topLeading, horizontalSpacing: context.theme.metrics.blockPadding, verticalSpacing: 6) {
                    GridRow {
                        ForEach(0..<model.columnCount, id: \.self) { column in
                            Text(model.headerText(column: column))
                                .font(context.theme.fonts.table.bold())
                                .foregroundStyle(context.theme.colors.textPrimary)
                                // Set GFM column alignment idiomatically: one
                                // representative cell per column carries the
                                // column's horizontal alignment. The header cell
                                // is that representative.
                                .gridColumnAlignment(model.horizontalAlignment(forColumn: column))
                        }
                    }
                    // The header/body rule must span all columns and live inside a
                    // GridRow; a bare Divider between rows has infinite ideal width
                    // under the scroll view's unbounded proposal and destabilizes
                    // the grid.
                    GridRow {
                        Divider()
                            .overlay(context.theme.colors.tableBorder)
                            .gridCellColumns(model.columnCount)
                    }
                    ForEach(0..<model.rowCount, id: \.self) { row in
                        GridRow {
                            ForEach(0..<model.columnCount, id: \.self) { column in
                                Text(model.bodyText(row: row, column: column))
                                    .font(context.theme.fonts.table)
                                    .foregroundStyle(context.theme.colors.textPrimary)
                            }
                        }
                    }
                }
                .padding(context.theme.metrics.blockPadding)
            }
            .overlay(
                RoundedRectangle(cornerRadius: context.theme.metrics.cornerRadius)
                    .stroke(context.theme.colors.tableBorder, lineWidth: 1)
            )
        }
    }

    /// Copies the table as tab-separated text and reports the interaction.
    /// Internal so headless tests can invoke it without simulating a tap.
    func performCopy() {
        let model = Model(table: table, theme: context.theme, config: context.config)
        Pasteboard.copy(model.copyText)
        context.analytics.didInteract(
            .tableCopied(rows: model.rowCount, columns: model.columnCount)
        )
    }

    /// The render-independent view model for a table. Exposed for headless
    /// assertions.
    struct Model {
        /// The number of columns (driven by the header).
        let columnCount: Int
        /// The number of body rows.
        let rowCount: Int

        private let theme: RillTheme
        private let header: [[Inline]]
        private let rows: [[[Inline]]]
        private let alignments: [ColumnAlignment]

        /// Builds a table model from its block, theme, and config.
        init(table: Table, theme: RillTheme, config: RenderConfig) {
            self.theme = theme
            self.header = table.header
            self.rows = table.rows
            self.alignments = table.alignments
            self.columnCount = table.header.count
            self.rowCount = table.rows.count
        }

        /// The SwiftUI alignment for a column, mapped from its
        /// ``ColumnAlignment`` (``ColumnAlignment/none`` ⇒ leading).
        func alignment(forColumn column: Int) -> Alignment {
            guard column < alignments.count else { return .leading }
            switch alignments[column] {
            case .none, .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }

        /// The `Grid` column alignment for a column, mapped from its
        /// ``ColumnAlignment`` (``ColumnAlignment/none`` ⇒ leading). Applied via
        /// `.gridColumnAlignment` so GFM `:---:` / `---:` alignment is honored by
        /// the idiomatic Grid mechanism rather than per-cell maxWidth frames.
        func horizontalAlignment(forColumn column: Int) -> HorizontalAlignment {
            guard column < alignments.count else { return .leading }
            switch alignments[column] {
            case .none, .left: return .leading
            case .center: return .center
            case .right: return .trailing
            }
        }

        /// The styled header text for a column.
        func headerText(column: Int) -> AttributedString {
            guard column < header.count else { return AttributedString() }
            return BlockInlineText.attributed(header[column], theme: theme)
        }

        /// The styled body text for a row/column cell.
        func bodyText(row: Int, column: Int) -> AttributedString {
            guard row < rows.count, column < rows[row].count else { return AttributedString() }
            return BlockInlineText.attributed(rows[row][column], theme: theme)
        }

        /// The tab-separated serialization placed on the pasteboard by copy.
        var copyText: String {
            var lines: [String] = []
            lines.append(header.map { BlockInlineText.plainText($0) }.joined(separator: "\t"))
            for row in rows {
                lines.append(row.map { BlockInlineText.plainText($0) }.joined(separator: "\t"))
            }
            return lines.joined(separator: "\n")
        }
    }
}
