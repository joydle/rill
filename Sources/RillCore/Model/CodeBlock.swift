/// A fenced or indented code block.
///
/// `CodeBlock` is a `Sendable`, `Hashable` value type. ``language`` is the
/// optional info-string language tag of a fenced block; ``content`` is the
/// verbatim code (newlines preserved); ``isClosed`` is `false` while a fence is
/// still open during streaming and `true` once the closing fence (or end of an
/// indented block) is seen, which lets the incremental parser keep an open fence
/// in the live tail.
public struct CodeBlock: Sendable, Hashable {
    /// The optional language tag from a fenced block's info string.
    public var language: String?

    /// The verbatim code content, with newlines preserved.
    public var content: String

    /// Whether the block's closing fence has been seen.
    public var isClosed: Bool

    /// Creates a code block.
    /// - Parameters:
    ///   - language: The optional language tag.
    ///   - content: The verbatim code content.
    ///   - isClosed: Whether the closing fence has been seen.
    public init(language: String?, content: String, isClosed: Bool) {
        self.language = language
        self.content = content
        self.isClosed = isClosed
    }

    /// Folds this code block's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(language)
        hasher.combine(content)
        hasher.combine(isClosed)
    }
}

/// A display math block (`$$ … $$` or `\[ … \]`).
///
/// `MathBlock` is a `Sendable`, `Hashable` value type. ``latex`` is the raw
/// LaTeX body; ``isClosed`` is `false` while the block awaits its closing
/// delimiter during streaming, so the incremental parser keeps it in the live
/// tail until it closes.
public struct MathBlock: Sendable, Hashable {
    /// The raw LaTeX body of the math block.
    public var latex: String

    /// Whether the block's closing delimiter has been seen.
    public var isClosed: Bool

    /// Creates a math block.
    /// - Parameters:
    ///   - latex: The raw LaTeX body.
    ///   - isClosed: Whether the closing delimiter has been seen.
    public init(latex: String, isClosed: Bool) {
        self.latex = latex
        self.isClosed = isClosed
    }

    /// Folds this math block's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(latex)
        hasher.combine(isClosed)
    }
}

/// A raw HTML block, captured verbatim.
///
/// `HTMLBlock` is a `Sendable`, `Hashable` value type holding the ``raw`` HTML
/// source. In v1 it is rendered as escaped text rather than interpreted.
public struct HTMLBlock: Sendable, Hashable {
    /// The captured raw HTML source.
    public var raw: String

    /// Creates an HTML block.
    /// - Parameter raw: The captured raw HTML source.
    public init(raw: String) {
        self.raw = raw
    }

    /// Folds this HTML block's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(raw)
    }
}
