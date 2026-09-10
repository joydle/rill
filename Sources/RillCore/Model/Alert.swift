/// The kind of a GitHub-style alert (callout) block.
///
/// GitHub alerts are block quotes whose first line is one of the five marker
/// tokens (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`).
/// `AlertKind` is the recognized type; ``displayTitle`` is the human-readable
/// heading the renderer shows above the callout body. Recognition is
/// case-insensitive, matching GitHub.
public enum AlertKind: String, Sendable, Hashable, CaseIterable {
    /// A neutral, informational callout (`[!NOTE]`).
    case note
    /// A helpful tip (`[!TIP]`).
    case tip
    /// Information the reader must not miss (`[!IMPORTANT]`).
    case important
    /// A cautionary note about potential problems (`[!WARNING]`).
    case warning
    /// A strong warning about risky or destructive actions (`[!CAUTION]`).
    case caution

    /// The default human-readable title rendered above the callout body, e.g.
    /// `"Note"`, `"Important"`.
    public var displayTitle: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    /// Recognizes a GitHub alert marker at the start of a block-quote's first
    /// (already `>`-stripped) line.
    ///
    /// The line must be *exactly* a marker token — `[!NOTE]` and so on, optionally
    /// followed by trailing whitespace — to qualify, so an ordinary quote that
    /// merely mentions `[!NOTE] see below` is **not** misclassified.
    ///
    /// - Parameter line: The block-quote first line with its `>` marker removed.
    /// - Returns: The recognized kind, or `nil` when the line is not a bare alert
    ///   marker.
    public static func marker(in line: Substring) -> AlertKind? {
        var s = line
        while let f = s.first, f == " " || f == "\t" { s = s.dropFirst() }
        guard s.first == "[", s.dropFirst().first == "!" else { return nil }
        var body = s.dropFirst(2) // drop "[!"
        var word = ""
        while let c = body.first, c != "]" {
            word.append(c)
            body = body.dropFirst()
        }
        guard body.first == "]" else { return nil }
        var trailing = body.dropFirst() // drop "]"
        while let l = trailing.last, l == " " || l == "\t" { trailing = trailing.dropLast() }
        guard trailing.isEmpty else { return nil }
        return AlertKind(rawValue: word.lowercased())
    }
}

/// A GitHub-style alert (callout) block: a styled container introduced by a
/// `[!NOTE]`-family marker.
///
/// `Alert` is a `Sendable`, `Hashable` value type. ``kind`` is the recognized
/// callout type and ``blocks`` are the nested block-level contents (everything in
/// the source block quote after the marker line). It renders as a themed callout
/// — icon, tinted left border, and title — rather than a plain block quote.
public struct Alert: Sendable, Hashable {
    /// The recognized callout type.
    public var kind: AlertKind

    /// The nested block-level content following the marker line.
    public var blocks: [Block]

    /// Creates an alert.
    /// - Parameters:
    ///   - kind: The callout type.
    ///   - blocks: The nested block-level content.
    public init(kind: AlertKind, blocks: [Block]) {
        self.kind = kind
        self.blocks = blocks
    }

    /// Folds this alert's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(kind.rawValue)
        Block.hash(blocks, into: &hasher)
    }
}

/// An unambiguous spelling of the alert model type ``Alert``.
///
/// Downstream modules that import SwiftUI — whose `Alert` value type collides
/// with this struct by short name — use `MarkdownAlert` to refer to the model
/// type without ambiguity, mirroring the ``InlineImage`` alias for ``Image``.
public typealias MarkdownAlert = Alert

/// A GFM footnote definition block (e.g. `[^id]: explanatory text`).
///
/// `FootnoteDefinition` is a `Sendable`, `Hashable` value type. ``marker`` is the
/// footnote label without its `[^` … `]` brackets, and ``blocks`` are the
/// definition body's block-level content. Inline references written as `[^id]`
/// are parsed as ``Citation`` inlines (with a `nil` index); the renderer maps a
/// reference to its definition by ``marker`` and lays the definitions out as a
/// numbered footnotes section at the end of the document.
public struct FootnoteDefinition: Sendable, Hashable {
    /// The footnote label, without the surrounding `[^` and `]`.
    public var marker: String

    /// The definition body's block-level content.
    public var blocks: [Block]

    /// Creates a footnote definition.
    /// - Parameters:
    ///   - marker: The footnote label (without brackets).
    ///   - blocks: The definition body's block-level content.
    public init(marker: String, blocks: [Block]) {
        self.marker = marker
        self.blocks = blocks
    }

    /// Folds this footnote definition's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(marker)
        Block.hash(blocks, into: &hasher)
    }
}
