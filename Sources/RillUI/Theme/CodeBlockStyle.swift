/// How fenced code blocks are presented by ``RillTheme``.
///
/// `CodeBlockStyle` is a `Sendable` value type. It selects between two layouts
/// that both cap how much code is shown before the block becomes interactive,
/// keeping long listings from dominating a streamed answer.
public enum CodeBlockStyle: Sendable, Hashable {
    /// An inline block that scrolls horizontally when a line overflows and
    /// vertically once it exceeds `maxPreviewLines`. The default presentation.
    /// - Parameter maxPreviewLines: The maximum number of code lines shown
    ///   before the block scrolls internally.
    case inlineScrollable(maxPreviewLines: Int)

    /// A truncated, tappable card that expands to a full-screen code viewer.
    /// - Parameter maxPreviewLines: The maximum number of code lines shown on
    ///   the card before truncation.
    case tappableCard(maxPreviewLines: Int)

    /// The maximum number of code lines previewed before the style scrolls or
    /// truncates, regardless of which case is selected.
    public var maxPreviewLines: Int {
        switch self {
        case let .inlineScrollable(maxPreviewLines),
             let .tappableCard(maxPreviewLines):
            return maxPreviewLines
        }
    }
}
