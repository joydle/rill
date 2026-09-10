import SwiftUI

/// Behavioral configuration for rendering, distinct from visual ``RillTheme``.
///
/// `RenderConfig` is a `Sendable` value type carrying the runtime hooks RillUI
/// needs from its host: whether newly streamed content animates in, how
/// citations resolve, how links are handled, and how images load. Every hook is
/// optional and absent in ``RenderConfig/default`` so the package works with no
/// configuration; hosts inject closures and adapters as needed. Stored closures
/// are `@Sendable` so the config can cross concurrency domains.
public struct RenderConfig: Sendable {
    /// How newly appended text in the live streaming tail is revealed.
    ///
    /// The reveal is SwiftUI-native and driven by the document update (a
    /// `withAnimation` transaction) rather than a per-character timer, so it
    /// stays in step with the incremental parser instead of running against it.
    /// Only the active tail block animates; committed (frozen) blocks never do —
    /// see ``TailAnimationPlan``.
    public enum AppendAnimation: Sendable, Hashable, CaseIterable {
        /// No reveal: appended text hard-cuts in.
        case none
        /// The whole newly appended run fades in together.
        case fade
        /// The newly appended run reveals word-by-word, left to right. This is
        /// the default.
        case word
    }

    /// Whether newly arriving (streamed) content animates its appearance.
    public var animatesAppearance: Bool

    /// How the live tail's newly appended text is revealed as it streams in.
    /// Defaults to ``AppendAnimation/word``.
    public var appendAnimation: AppendAnimation

    /// The duration, in seconds, of the append reveal animation. Ignored when
    /// ``appendAnimation`` is ``AppendAnimation/none``. Defaults to `0.22`.
    public var appendAnimationDuration: TimeInterval

    /// Resolves a citation marker (e.g. `"1"`) to a ``CitationTarget``, or `nil`
    /// when the marker has no known source (the citation then renders as plain
    /// text).
    public var citationResolver: (@Sendable (String) -> CitationTarget?)?

    /// Handles a tapped link URL. When `nil`, RillUI uses its default open
    /// behavior.
    public var linkHandler: (@Sendable (URL) -> Void)?

    /// Loads images asynchronously. When `nil`, images render as their alt text.
    public var imageLoader: ImageLoading?

    /// Creates a render configuration.
    /// - Parameters:
    ///   - animatesAppearance: Whether streamed content animates in. Defaults to
    ///     `true`.
    ///   - appendAnimation: How the live tail's appended text is revealed.
    ///     Defaults to ``AppendAnimation/word``.
    ///   - appendAnimationDuration: The reveal duration in seconds. Defaults to
    ///     `0.22`.
    ///   - citationResolver: Optional citation resolver. Defaults to `nil`.
    ///   - linkHandler: Optional link tap handler. Defaults to `nil`.
    ///   - imageLoader: Optional async image loader. Defaults to `nil`.
    public init(
        animatesAppearance: Bool = true,
        appendAnimation: AppendAnimation = .word,
        appendAnimationDuration: TimeInterval = 0.22,
        citationResolver: (@Sendable (String) -> CitationTarget?)? = nil,
        linkHandler: (@Sendable (URL) -> Void)? = nil,
        imageLoader: ImageLoading? = nil
    ) {
        self.animatesAppearance = animatesAppearance
        self.appendAnimation = appendAnimation
        self.appendAnimationDuration = appendAnimationDuration
        self.citationResolver = citationResolver
        self.linkHandler = linkHandler
        self.imageLoader = imageLoader
    }

    /// The built-in configuration: appearance animates and no host hooks are
    /// installed.
    public static let `default` = RenderConfig()
}
