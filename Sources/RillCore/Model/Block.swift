/// A block-level Markdown node: the top-level structural elements of a document.
///
/// `Block` is a `Sendable`, `Hashable` value type. Each case wraps a dedicated
/// value type (or, for ``thematicBreak``, carries no payload).
///
/// It exposes a content-derived ``id`` of type ``NodeID`` used by the incremental
/// engine to memoize and reuse unchanged committed blocks. That `id` is **not**
/// unique among siblings — two identical blocks (e.g. two `---`) share it — so
/// `Block` deliberately does **not** conform to `Identifiable`: render `[Block]`
/// with a position-based key, e.g. `ForEach(Array(blocks.enumerated()), id: \.offset)`.
public indirect enum Block: Sendable, Hashable {
    /// An ATX/setext heading (levels 1–6).
    case heading(Heading)

    /// A paragraph of inline content.
    case paragraph(Paragraph)

    /// A block quote containing nested blocks.
    case blockQuote(BlockQuote)

    /// A GitHub-style alert/callout (`> [!NOTE]`, `> [!WARNING]`, …).
    case alert(Alert)

    /// An ordered or unordered list.
    case list(List)

    /// A fenced or indented code block.
    case codeBlock(CodeBlock)

    /// A GFM pipe table.
    case table(Table)

    /// A thematic break (`---`, `***`, `___`).
    case thematicBreak

    /// A display math block (`$$ … $$` or `\[ … \]`).
    case mathBlock(MathBlock)

    /// A raw HTML block, rendered as escaped text in v1.
    case htmlBlock(HTMLBlock)

    /// A GFM footnote definition (`[^id]: text`), collected and rendered as a
    /// numbered footnotes section at the end of the document.
    case footnoteDefinition(FootnoteDefinition)

    /// A content-derived identity for this block (a seedless FNV-1a digest of the
    /// case discriminator and payload).
    ///
    /// Equal blocks — including deeply nested ones — share an `id`, which is what
    /// lets the incremental engine reuse unchanged committed blocks. It is a
    /// content key, **not** a unique per-position identity: two identical sibling
    /// blocks share it, so do not use it as a SwiftUI `ForEach` id (key by
    /// position instead).
    public var id: NodeID {
        var hasher = ContentHasher()
        hash(into: &hasher)
        return NodeID(hash: hasher.value)
    }

    /// Folds this block's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        switch self {
        case .heading(let h):
            hasher.combine(tag: 0)
            h.hash(into: &hasher)
        case .paragraph(let p):
            hasher.combine(tag: 1)
            p.hash(into: &hasher)
        case .blockQuote(let bq):
            hasher.combine(tag: 2)
            bq.hash(into: &hasher)
        case .alert(let alert):
            hasher.combine(tag: 9)
            alert.hash(into: &hasher)
        case .footnoteDefinition(let def):
            hasher.combine(tag: 10)
            def.hash(into: &hasher)
        case .list(let list):
            hasher.combine(tag: 3)
            list.hash(into: &hasher)
        case .codeBlock(let cb):
            hasher.combine(tag: 4)
            cb.hash(into: &hasher)
        case .table(let table):
            hasher.combine(tag: 5)
            table.hash(into: &hasher)
        case .thematicBreak:
            hasher.combine(tag: 6)
        case .mathBlock(let m):
            hasher.combine(tag: 7)
            m.hash(into: &hasher)
        case .htmlBlock(let html):
            hasher.combine(tag: 8)
            html.hash(into: &hasher)
        }
    }

    /// Folds a sequence of blocks into the digest, framed by its count.
    static func hash(_ blocks: [Block], into hasher: inout ContentHasher) {
        hasher.combine(blocks.count)
        for block in blocks {
            block.hash(into: &hasher)
        }
    }
}
