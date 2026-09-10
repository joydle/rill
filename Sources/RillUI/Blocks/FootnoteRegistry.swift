import RillCore

/// A document-scoped index of GFM footnote definitions, assigning each a stable
/// 1-based number.
///
/// `FootnoteRegistry` is built once per ``Document`` render from its
/// ``Block/footnoteDefinition(_:)`` blocks (in document order). It lets the inline
/// renderer map a footnote reference (`[^id]`, parsed as a ``Citation`` with a
/// `nil` index) to its definition number so the reference renders as a tappable
/// superscript marker, and lets ``FootnotesSectionView`` lay the definitions out
/// as a numbered section at the end of the document.
public struct FootnoteRegistry: Sendable, Equatable {
    /// One numbered footnote definition.
    public struct Entry: Sendable, Equatable {
        /// The 1-based footnote number shown in references and the section.
        public let number: Int
        /// The footnote label (without `[^` … `]`), used to match references.
        public let marker: String
        /// The definition's block-level content.
        public let blocks: [Block]
    }

    /// The numbered definitions, in document (definition) order.
    public let entries: [Entry]

    /// Marker → number lookup, precomputed for O(1) reference resolution.
    private let numbers: [String: Int]

    /// An empty registry (no footnotes); the default carried by a context.
    public static let empty = FootnoteRegistry(entries: [])

    /// Creates a registry from already-numbered entries.
    public init(entries: [Entry]) {
        self.entries = entries
        var map: [String: Int] = [:]
        for entry in entries where map[entry.marker] == nil {
            map[entry.marker] = entry.number
        }
        self.numbers = map
    }

    /// Builds a registry by collecting every top-level footnote definition in a
    /// document, numbering them 1…N in order of appearance. Duplicate markers keep
    /// their first number.
    /// - Parameter document: The document to index.
    public init(document: Document) {
        var entries: [Entry] = []
        var seen = Set<String>()
        for block in document.blocks {
            guard case .footnoteDefinition(let def) = block else { continue }
            guard !seen.contains(def.marker) else { continue }
            seen.insert(def.marker)
            entries.append(Entry(number: entries.count + 1, marker: def.marker, blocks: def.blocks))
        }
        self.init(entries: entries)
    }

    /// The assigned number for a reference marker, or `nil` if undefined.
    /// - Parameter marker: The footnote label to look up.
    public func number(for marker: String) -> Int? { numbers[marker] }

    /// Whether the document has no footnote definitions.
    public var isEmpty: Bool { entries.isEmpty }
}
