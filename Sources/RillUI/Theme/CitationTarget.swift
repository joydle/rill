/// The resolved destination of a citation marker.
///
/// `CitationTarget` is a `Sendable` value type produced by
/// ``RenderConfig/citationResolver``. A citation such as `[1]` is mapped to a
/// human-readable ``title`` and an optional ``url``; when a marker resolves to
/// `nil` the citation renders as plain text instead of an interactive pill.
public struct CitationTarget: Sendable, Hashable {
    /// The human-readable title shown for the citation (e.g. a source name).
    public var title: String

    /// The optional destination URL, as a string, opened when the citation is
    /// tapped. `nil` for citations that have no navigable target.
    public var url: String?

    /// Creates a citation target.
    /// - Parameters:
    ///   - title: The human-readable title shown for the citation.
    ///   - url: The optional destination URL as a string.
    public init(title: String, url: String?) {
        self.title = title
        self.url = url
    }
}
