/// An ATX or setext heading block.
///
/// `Heading` is a `Sendable`, `Hashable` value type. ``level`` is the heading
/// level (1–6) and ``inlines`` is its inline-formatted content.
public struct Heading: Sendable, Hashable {
    /// The heading level, 1 (largest) through 6 (smallest).
    public var level: Int

    /// The heading's inline-formatted content.
    public var inlines: [Inline]

    /// Creates a heading.
    /// - Parameters:
    ///   - level: The heading level (1–6).
    ///   - inlines: The heading's inline content.
    public init(level: Int, inlines: [Inline]) {
        self.level = level
        self.inlines = inlines
    }

    /// Folds this heading's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(level)
        Inline.hash(inlines, into: &hasher)
    }
}

/// A paragraph block: a run of inline content separated from neighbors by blank
/// lines.
///
/// `Paragraph` is a `Sendable`, `Hashable` value type holding its
/// inline-formatted ``inlines``.
public struct Paragraph: Sendable, Hashable {
    /// The paragraph's inline-formatted content.
    public var inlines: [Inline]

    /// Creates a paragraph.
    /// - Parameter inlines: The paragraph's inline content.
    public init(inlines: [Inline]) {
        self.inlines = inlines
    }

    /// Folds this paragraph's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        Inline.hash(inlines, into: &hasher)
    }
}

/// A block quote: a container of nested block-level content.
///
/// `BlockQuote` is a `Sendable`, `Hashable` value type holding its child
/// ``blocks``, which may themselves be quotes, lists, code, etc.
public struct BlockQuote: Sendable, Hashable {
    /// The nested block-level content of the quote.
    public var blocks: [Block]

    /// Creates a block quote.
    /// - Parameter blocks: The nested block-level content.
    public init(blocks: [Block]) {
        self.blocks = blocks
    }

    /// Folds this quote's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        Block.hash(blocks, into: &hasher)
    }
}
