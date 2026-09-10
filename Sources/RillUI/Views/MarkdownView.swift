import SwiftUI
import RillCore
import RillAnalytics

/// Renders a complete Markdown string as a static, non-streaming view.
///
/// `MarkdownView` is the simplest entry point: hand it a finished Markdown
/// string, a ``RillTheme``, and a ``RenderConfig``, and it parses once and
/// renders the result with a ``DocumentView``. Use it for completed content (for
/// example a finished chat turn); for live token-by-token streaming use
/// ``StreamingMarkdownView`` fed by a ``MarkdownSource``.
///
/// Parsing goes through the same ``IncrementalParser`` as the streaming path
/// (fed the whole string in one shot), so a `MarkdownView` and a fully-streamed
/// ``MarkdownSource`` produce a byte-identical ``Document``.
public struct MarkdownView: View {

    /// The document parsed once from the input string.
    private let document: Document

    /// The visual theme threaded to the underlying ``DocumentView``.
    private let theme: RillTheme

    /// The behavioural configuration threaded to the underlying ``DocumentView``.
    private let config: RenderConfig

    /// The analytics sink for interaction and render events.
    private let analytics: any MarkdownAnalytics

    /// Creates a static Markdown view by parsing the given string once.
    /// - Parameters:
    ///   - markdown: The complete Markdown text to render.
    ///   - theme: The visual theme. Defaults to ``RillTheme/default``.
    ///   - config: The behavioural configuration. Defaults to
    ///     ``RenderConfig/default``.
    ///   - analytics: The analytics sink for interaction events. Defaults to
    ///     ``NoopAnalytics``.
    public init(
        _ markdown: String,
        theme: RillTheme = .default,
        config: RenderConfig = .default,
        analytics: any MarkdownAnalytics = NoopAnalytics()
    ) {
        self.document = MarkdownView.parse(markdown)
        self.theme = theme
        self.config = config
        self.analytics = analytics
    }

    /// Parses the Markdown string once and renders it through a ``DocumentView``.
    public var body: some View {
        DocumentView(document, theme: theme, config: config, analytics: analytics)
    }

    /// Parses a complete Markdown string into a ``Document`` once, using the same
    /// incremental engine as the streaming path fed in one shot.
    ///
    /// Exposed so callers (and tests) can obtain the parsed model without
    /// building a view, and to guarantee static and streaming parses agree.
    /// - Parameter markdown: The complete Markdown text.
    /// - Returns: The parsed ``Document``.
    public static func parse(_ markdown: String) -> Document {
        let parser = IncrementalParser()
        parser.consume(snapshot: markdown)
        return parser.document
    }
}
