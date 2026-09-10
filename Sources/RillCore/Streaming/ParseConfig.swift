/// Configuration that tunes which Markdown/GFM extensions the parser recognizes.
///
/// `ParseConfig` is a `Sendable` value type. It governs optional inline features
/// (GFM strikethrough, bare-URL autolinks, `$…$` math, `[1]`/`[^id]` citations)
/// so a consumer can disable any extension that conflicts with its content (for
/// example turning off `$` math for text full of currency amounts). The default
/// enables the full practical CommonMark + GFM subset Rill targets.
public struct ParseConfig: Sendable, Hashable {
    /// Whether GFM `~~strikethrough~~` is recognized.
    public var strikethrough: Bool

    /// Whether bare URLs (e.g. `https://example.com` without angle brackets) are
    /// turned into autolinks.
    public var bareURLAutolinks: Bool

    /// Whether single-dollar inline math (`$x$`) is recognized. Backslash-paren
    /// math (`\( … \)`) is always recognized regardless of this flag.
    public var dollarMath: Bool

    /// Whether citation markers (`[1]`, `[^id]`) are recognized as
    /// ``Inline/citation(_:)`` nodes rather than literal text.
    public var citations: Bool

    /// Creates a parse configuration.
    /// - Parameters:
    ///   - strikethrough: Enables GFM strikethrough. Defaults to `true`.
    ///   - bareURLAutolinks: Enables bare-URL autolinking. Defaults to `true`.
    ///   - dollarMath: Enables `$…$` inline math. Defaults to `true`.
    ///   - citations: Enables `[1]`/`[^id]` citations. Defaults to `true`.
    public init(
        strikethrough: Bool = true,
        bareURLAutolinks: Bool = true,
        dollarMath: Bool = true,
        citations: Bool = true
    ) {
        self.strikethrough = strikethrough
        self.bareURLAutolinks = bareURLAutolinks
        self.dollarMath = dollarMath
        self.citations = citations
    }

    /// The default configuration: the full practical CommonMark + GFM subset.
    public static let `default` = ParseConfig()
}
