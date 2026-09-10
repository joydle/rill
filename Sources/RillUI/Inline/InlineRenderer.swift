import SwiftUI
import RillCore
import RillAnalytics

/// Lowers a run of ``Inline`` nodes into styled text and, where an
/// `AttributedString` cannot express them, into dedicated inline view segments.
///
/// Most inline content — text, soft/hard breaks, emphasis, strong,
/// strikethrough, inline code, links, citations (as their bracketed marker in
/// flowing text), and raw HTML (escaped) — flattens into a single
/// `AttributedString` via ``attributed(_:theme:config:)``. That is the fast
/// path the block renderers use for plain paragraphs and headings.
///
/// Two inline kinds have no `AttributedString` representation: ``Inline/image``
/// (an async-loaded picture) and ``Inline/mathInline`` (a TeX-laid-out
/// equation). For mixed content containing those, ``segments(_:theme:config:)``
/// splits the run into an ordered list of ``InlineSegment``s — contiguous
/// attributed text interleaved with image and math view segments — so a view
/// can lay them out together while keeping the text path attributed.
///
/// `InlineRenderer` is a stateless namespace; all entry points are pure given
/// their theme and config, so they are safe to call from view-model builders in
/// headless tests.
public enum InlineRenderer {

    // MARK: - Attributed text path

    /// Flattens an inline run into a single styled `AttributedString`.
    ///
    /// Emphasis nests: a `*italic*` inside `**bold**` produces a run carrying
    /// *both* the ``SwiftUI/InlinePresentationIntent/emphasized`` and
    /// ``SwiftUI/InlinePresentationIntent/stronglyEmphasized`` intents.
    /// Inline code uses ``RillTheme/Fonts/code``; links carry their destination
    /// as the `.link` attribute plus the theme link color; strikethrough sets
    /// the single strikethrough style. Cases without an attributed
    /// representation (images, inline math) degrade to readable text — alt text
    /// and raw LaTeX respectively — so a streamed line is never blank. Use
    /// ``segments(_:theme:config:)`` when those need real inline views.
    ///
    /// - Parameters:
    ///   - inlines: The inline run to lower.
    ///   - theme: The theme supplying fonts and colors.
    ///   - config: The behavioural configuration (unused by the pure text path
    ///     today; threaded for symmetry and future link/citation styling hooks).
    /// - Returns: The styled attributed string.
    public static func attributed(
        _ inlines: [Inline],
        theme: RillTheme,
        config: RenderConfig
    ) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            result.append(attributed(inline, theme: theme, config: config))
        }
        return result
    }

    /// Lowers a single inline node into a styled `AttributedString`.
    private static func attributed(
        _ inline: Inline,
        theme: RillTheme,
        config: RenderConfig
    ) -> AttributedString {
        switch inline {
        case .text(let s):
            return AttributedString(s)

        case .softBreak:
            // A soft break is a wrap point; render as a space.
            return AttributedString(" ")

        case .lineBreak:
            // A hard break forces a newline.
            return AttributedString("\n")

        case .emphasis(let children):
            var s = attributed(children, theme: theme, config: config)
            addIntent(.emphasized, to: &s)
            return s

        case .strong(let children):
            var s = attributed(children, theme: theme, config: config)
            addIntent(.stronglyEmphasized, to: &s)
            return s

        case .strikethrough(let children):
            var s = attributed(children, theme: theme, config: config)
            addIntent(.strikethrough, to: &s)
            s.strikethroughStyle = .single
            return s

        case .code(let code):
            var s = AttributedString(code)
            s.font = theme.fonts.code
            s.backgroundColor = theme.colors.codeBackground
            return s

        case .link(let link):
            var s = attributed(link.inlines, theme: theme, config: config)
            if let url = URL(string: link.url) {
                s.link = url
            }
            s.foregroundColor = theme.colors.link
            s.underlineStyle = .single
            return s

        case .image(let image):
            // No attributed representation; degrade to alt text. Mixed content
            // that needs a real inline image uses `segments(_:theme:config:)`.
            return AttributedString(image.alt.isEmpty ? image.url : image.alt)

        case .mathInline(let latex):
            // No attributed representation; degrade to the raw LaTeX so a
            // streamed equation is never blank.
            return AttributedString(latex)

        case .citation(let citation):
            var s = AttributedString("[\(citation.marker)]")
            s.foregroundColor = theme.colors.citation
            return s

        case .rawHTML(let raw):
            // Escaped text in v1: shown verbatim, never interpreted.
            return AttributedString(raw)
        }
    }

    /// Merges a presentation intent into an attributed string's existing intents
    /// across every run, preserving nested intents (e.g. an inner
    /// ``SwiftUI/InlinePresentationIntent/emphasized`` survives an outer
    /// ``SwiftUI/InlinePresentationIntent/stronglyEmphasized``).
    private static func addIntent(
        _ intent: InlinePresentationIntent,
        to string: inout AttributedString
    ) {
        for run in string.runs {
            let existing = string[run.range].inlinePresentationIntent ?? []
            string[run.range].inlinePresentationIntent = existing.union(intent)
        }
    }

    // MARK: - Segmented path (images & inline math become views)

    /// Splits an inline run into ordered ``InlineSegment``s.
    ///
    /// Contiguous attributed-expressible inlines coalesce into a single
    /// ``InlineSegment/text(_:)`` segment; each ``Inline/image`` and
    /// ``Inline/mathInline`` becomes its own ``InlineSegment/image(_:)`` or
    /// ``InlineSegment/math(_:)`` segment so a view can place a real picture or
    /// laid-out equation between text spans. Empty text segments are dropped so
    /// adjacent image/math segments do not accrue blank text.
    ///
    /// - Parameters:
    ///   - inlines: The inline run to segment.
    ///   - theme: The theme used to style the text segments.
    ///   - config: The behavioural configuration.
    /// - Returns: The ordered segments, ready to lay out in a view.
    public static func segments(
        _ inlines: [Inline],
        theme: RillTheme,
        config: RenderConfig
    ) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var pending: [Inline] = []

        func flushText() {
            guard !pending.isEmpty else { return }
            let text = attributed(pending, theme: theme, config: config)
            if !text.characters.isEmpty {
                segments.append(.text(text))
            }
            pending.removeAll(keepingCapacity: true)
        }

        for inline in inlines {
            switch inline {
            case .image(let image):
                flushText()
                segments.append(.image(image))
            case .mathInline(let latex):
                flushText()
                segments.append(.math(latex))
            case .citation(let citation):
                // Numbered citations (e.g. `[1]`) stay inline as flowing
                // attributed text, so the whole paragraph remains a single,
                // naturally-wrapping, evenly-spaced `Text` rather than a flow of
                // hand-placed word/pill boxes (which spaces unevenly). Only a
                // footnote-style reference (no number; resolved against the
                // registry) breaks out to a view, to render as a superscript.
                if citation.index == nil {
                    flushText()
                    segments.append(.citation(citation))
                } else {
                    pending.append(inline)
                }
            default:
                pending.append(inline)
            }
        }
        flushText()
        return segments
    }

    // MARK: - Interaction

    /// Reports a link activation: fires
    /// ``MarkdownInteraction/linkTapped(url:)`` and, when the host installed a
    /// ``RenderConfig/linkHandler``, invokes it with the parsed `URL`.
    ///
    /// - Parameters:
    ///   - url: The link destination as written in the source.
    ///   - context: The render context supplying the analytics sink and config.
    public static func handleLinkTap(url: String, context: BlockRenderContext) {
        context.analytics.didInteract(.linkTapped(url: url))
        if let handler = context.config.linkHandler, let parsed = URL(string: url) {
            handler(parsed)
        }
    }
}

/// One piece of a segmented inline run produced by
/// ``InlineRenderer/segments(_:theme:config:)``.
///
/// A run of inlines lowers to an ordered list of these: attributed text spans
/// interleaved with images and inline math, the latter two needing real SwiftUI
/// views because an `AttributedString` cannot represent them.
public enum InlineSegment: Sendable {
    /// A span of attributed text (the coalesced attributed-expressible inlines).
    case text(AttributedString)

    /// An inline image to load and place between text spans.
    case image(InlineImage)

    /// Inline math; the payload is the raw LaTeX to lay out and draw.
    case math(String)

    /// A citation reference to render as an interactive pill.
    case citation(Citation)
}
