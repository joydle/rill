/// An inline-level Markdown node: the leaf content that flows inside blocks.
///
/// `Inline` is a `Sendable`, `Hashable` value type. Emphasis-family cases nest
/// recursively, mirroring the CommonMark/GFM inline grammar.
///
/// It exposes a content-derived ``id`` of type ``NodeID`` (equal inlines share
/// it). Like ``Block``, that `id` is a content key, not a unique per-position
/// identity, so `Inline` does **not** conform to `Identifiable`; key any
/// `ForEach` over inlines by position.
public indirect enum Inline: Sendable, Hashable {
    /// Literal text with no inline formatting.
    case text(String)

    /// A soft line break (a single newline inside a paragraph), rendered as a
    /// space or wrap point.
    case softBreak

    /// A hard line break (two trailing spaces or a backslash), rendered as a
    /// forced newline.
    case lineBreak

    /// Emphasized (`*italic*` / `_italic_`) content.
    case emphasis([Inline])

    /// Strongly emphasized (`**bold**` / `__bold__`) content.
    case strong([Inline])

    /// Struck-through (`~~del~~`, GFM) content.
    case strikethrough([Inline])

    /// An inline code span (`` `code` ``); the payload is the literal code text.
    case code(String)

    /// A hyperlink, including autolinks.
    case link(Link)

    /// An image; rendered asynchronously with alt-text fallback.
    case image(Image)

    /// Inline math (`\( … \)` or `$ … $`); the payload is the raw LaTeX.
    case mathInline(String)

    /// A citation reference (e.g. `[1]` or `[^id]`), rendered as a pill.
    case citation(Citation)

    /// Raw inline HTML, captured verbatim and rendered as escaped text in v1.
    case rawHTML(String)

    /// A stable, content-derived identity for this inline.
    ///
    /// The `id` is a content digest (FNV-1a) of the case discriminator and
    /// payload — it carries no source range. Equal inlines (including nested
    /// ones) therefore share an `id`, and distinct inlines do not collide.
    public var id: NodeID {
        var hasher = ContentHasher()
        hash(into: &hasher)
        return NodeID(hash: hasher.value)
    }

    /// Folds this inline's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        switch self {
        case .text(let s):
            hasher.combine(tag: 0)
            hasher.combine(s)
        case .softBreak:
            hasher.combine(tag: 1)
        case .lineBreak:
            hasher.combine(tag: 2)
        case .emphasis(let children):
            hasher.combine(tag: 3)
            Inline.hash(children, into: &hasher)
        case .strong(let children):
            hasher.combine(tag: 4)
            Inline.hash(children, into: &hasher)
        case .strikethrough(let children):
            hasher.combine(tag: 5)
            Inline.hash(children, into: &hasher)
        case .code(let s):
            hasher.combine(tag: 6)
            hasher.combine(s)
        case .link(let link):
            hasher.combine(tag: 7)
            link.hash(into: &hasher)
        case .image(let image):
            hasher.combine(tag: 8)
            image.hash(into: &hasher)
        case .mathInline(let s):
            hasher.combine(tag: 9)
            hasher.combine(s)
        case .citation(let citation):
            hasher.combine(tag: 10)
            citation.hash(into: &hasher)
        case .rawHTML(let s):
            hasher.combine(tag: 11)
            hasher.combine(s)
        }
    }

    /// Folds a sequence of inlines into the digest, framed by its count.
    static func hash(_ inlines: [Inline], into hasher: inout ContentHasher) {
        hasher.combine(inlines.count)
        for inline in inlines {
            inline.hash(into: &hasher)
        }
    }
}
