/// A bullet or ordered list block.
///
/// `List` is a `Sendable`, `Hashable` value type. ``isOrdered`` distinguishes
/// ordered (`1.`) from bullet (`-`/`*`/`+`) lists; ``start`` is the first
/// ordinal of an ordered list; ``isTight`` reflects CommonMark tight/loose
/// spacing (tight lists omit inter-item blank-line spacing).
public struct List: Sendable, Hashable {
    /// The list's items, in document order.
    public var items: [ListItem]

    /// Whether the list is ordered (numbered) rather than a bullet list.
    public var isOrdered: Bool

    /// The starting ordinal for an ordered list (ignored for bullet lists).
    public var start: Int

    /// Whether the list is tight (no blank lines between items contribute to
    /// loose spacing).
    public var isTight: Bool

    /// Creates a list.
    /// - Parameters:
    ///   - items: The list's items in document order.
    ///   - isOrdered: Whether the list is ordered.
    ///   - start: The starting ordinal for an ordered list.
    ///   - isTight: Whether the list is tight.
    public init(items: [ListItem], isOrdered: Bool, start: Int, isTight: Bool) {
        self.items = items
        self.isOrdered = isOrdered
        self.start = start
        self.isTight = isTight
    }

    /// Folds this list's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(isOrdered)
        hasher.combine(start)
        hasher.combine(isTight)
        hasher.combine(items.count)
        for item in items {
            item.hash(into: &hasher)
        }
    }
}

/// A single item within a ``List``.
///
/// `ListItem` is a `Sendable`, `Hashable` value type holding nested block-level
/// ``blocks``. ``checkbox`` encodes a GFM task-list state: `nil` for a plain
/// item, `false` for `- [ ]`, and `true` for `- [x]`.
public struct ListItem: Sendable, Hashable {
    /// The nested block-level content of the item.
    public var blocks: [Block]

    /// The GFM task-list checkbox state: `nil` (none), `false` (unchecked), or
    /// `true` (checked).
    public var checkbox: Bool?

    /// Creates a list item.
    /// - Parameters:
    ///   - blocks: The nested block-level content.
    ///   - checkbox: The GFM task-list checkbox state, or `nil`.
    public init(blocks: [Block], checkbox: Bool?) {
        self.blocks = blocks
        self.checkbox = checkbox
    }

    /// Folds this item's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(checkbox)
        Block.hash(blocks, into: &hasher)
    }
}

/// Alias to disambiguate from `SwiftUI.List` when both modules are imported.
public typealias MarkdownList = List
