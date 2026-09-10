/// A hyperlink inline node.
///
/// `Link` is a `Sendable`, `Hashable` value type. Its visible content is a
/// sequence of ``Inline`` nodes (so links may contain emphasis, code, etc.);
/// ``url`` is the destination as written, and ``title`` is the optional title
/// text from `[text](url "title")`.
public struct Link: Sendable, Hashable {
    /// The link's visible, inline-formatted content.
    public var inlines: [Inline]

    /// The destination URL as written in the source.
    public var url: String

    /// The optional title (the `"title"` in `[text](url "title")`).
    public var title: String?

    /// Creates a link.
    /// - Parameters:
    ///   - inlines: The link's visible, inline-formatted content.
    ///   - url: The destination URL as written.
    ///   - title: The optional title text.
    public init(inlines: [Inline], url: String, title: String?) {
        self.inlines = inlines
        self.url = url
        self.title = title
    }

    /// Folds this link's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        Inline.hash(inlines, into: &hasher)
        hasher.combine(url)
        hasher.combine(title)
    }
}

/// An image inline node.
///
/// `Image` is a `Sendable`, `Hashable` value type. ``alt`` is the alt text used
/// as a loading/fallback label, ``url`` is the source as written, and ``title``
/// is the optional title from `![alt](url "title")`.
public struct Image: Sendable, Hashable {
    /// The alt text, used as a fallback when the image cannot be shown.
    public var alt: String

    /// The image source URL as written in the source.
    public var url: String

    /// The optional title text.
    public var title: String?

    /// Creates an image.
    /// - Parameters:
    ///   - alt: The alt/fallback text.
    ///   - url: The image source URL as written.
    ///   - title: The optional title text.
    public init(alt: String, url: String, title: String?) {
        self.alt = alt
        self.url = url
        self.title = title
    }

    /// Folds this image's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(alt)
        hasher.combine(url)
        hasher.combine(title)
    }
}

/// An unambiguous spelling of the image model type ``Image``.
///
/// The `RillCore` module name is shadowed by the `RillCore` namespace enum, so
/// `RillCore.Image` resolves to the enum's (non-existent) member rather than the
/// module's ``Image`` struct. Downstream modules that also import SwiftUI — whose
/// `Image` view collides with this struct by short name — use `InlineImage` to
/// refer to the model type without ambiguity.
public typealias InlineImage = Image

/// A citation reference inline node (e.g. `[1]` or `[^id]`).
///
/// `Citation` is a `Sendable`, `Hashable` value type. ``marker`` is the literal
/// marker text (`"1"`, `"id"`, …) and ``index`` is its resolved ordinal
/// position when known, used to render a numbered pill.
public struct Citation: Sendable, Hashable {
    /// The literal citation marker text, without surrounding brackets.
    public var marker: String

    /// The resolved ordinal index of the citation, if known.
    public var index: Int?

    /// Creates a citation.
    /// - Parameters:
    ///   - marker: The literal marker text.
    ///   - index: The resolved ordinal index, if known.
    public init(marker: String, index: Int?) {
        self.marker = marker
        self.index = index
    }

    /// Folds this citation's content into a deterministic digest.
    func hash(into hasher: inout ContentHasher) {
        hasher.combine(marker)
        hasher.combine(index)
    }
}

/// Alias to disambiguate from `SwiftUI.Link` when both modules are imported.
public typealias InlineLink = Link
