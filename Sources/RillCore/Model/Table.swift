/// The horizontal alignment of a GFM table column.
///
/// Determined by the delimiter row's colons: `---` ⇒ ``none`` (default),
/// `:---` ⇒ ``left``, `:---:` ⇒ ``center``, `---:` ⇒ ``right``.
public enum ColumnAlignment: Sendable, Hashable {
    /// No explicit alignment; renderers use their default.
    case none
    /// Left-aligned (`:---`).
    case left
    /// Center-aligned (`:---:`).
    case center
    /// Right-aligned (`---:`).
    case right
}

/// A GFM pipe table block.
///
/// `Table` is a `Sendable`, `Hashable` value type. ``header`` is the row of
/// header cells (each cell a sequence of ``Inline``); ``rows`` is the body, a
/// list of rows of cells; ``alignments`` is the per-column alignment parsed from
/// the delimiter row.
public struct Table: Sendable, Hashable {
    /// The header row: one cell per column, each cell inline-formatted.
    public var header: [[Inline]]

    /// The body rows: each row is a list of inline-formatted cells.
    public var rows: [[[Inline]]]

    /// The per-column alignment from the delimiter row.
    public var alignments: [ColumnAlignment]

    /// Creates a table.
    /// - Parameters:
    ///   - header: The header row's cells.
    ///   - rows: The body rows.
    ///   - alignments: The per-column alignments.
    public init(header: [[Inline]], rows: [[[Inline]]], alignments: [ColumnAlignment]) {
        self.header = header
        self.rows = rows
        self.alignments = alignments
    }

    /// Folds this table's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(header.count)
        for cell in header {
            Inline.hash(cell, into: &hasher)
        }
        hasher.combine(rows.count)
        for row in rows {
            hasher.combine(row.count)
            for cell in row {
                Inline.hash(cell, into: &hasher)
            }
        }
        hasher.combine(alignments.count)
        for alignment in alignments {
            switch alignment {
            case .none: hasher.combine(tag: 0)
            case .left: hasher.combine(tag: 1)
            case .center: hasher.combine(tag: 2)
            case .right: hasher.combine(tag: 3)
            }
        }
    }
}

/// Alias to disambiguate from `SwiftUI.Table` when both modules are imported.
public typealias MarkdownTable = Table
