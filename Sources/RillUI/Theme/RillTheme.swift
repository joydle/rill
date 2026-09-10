import SwiftUI
import RillCore

/// The complete visual styling for rendered Markdown.
///
/// `RillTheme` is a `Sendable` value type bundling the fonts, colors, metrics,
/// and code-block presentation used by every RillUI view. Its
/// ``RillTheme/default`` is fully populated — no slot is `nil` — so the package
/// looks good with zero configuration. Hosts build their own
/// theme by copying ``RillTheme/default`` and overriding fields.
public struct RillTheme: Sendable {
    /// The fonts used for body text, headings, code, blockquotes, and tables.
    public var fonts: Fonts

    /// The colors used for text, links, code backgrounds, quote bars,
    /// citations, and table borders.
    public var colors: Colors

    /// The spacing, indentation, padding, and corner-radius metrics.
    public var metrics: Metrics

    /// How fenced code blocks are presented.
    public var codeBlock: CodeBlockStyle

    /// Creates a theme.
    /// - Parameters:
    ///   - fonts: The font set.
    ///   - colors: The color set.
    ///   - metrics: The layout metrics.
    ///   - codeBlock: The code-block presentation style.
    public init(fonts: Fonts, colors: Colors, metrics: Metrics, codeBlock: CodeBlockStyle) {
        self.fonts = fonts
        self.colors = colors
        self.metrics = metrics
        self.codeBlock = codeBlock
    }

    /// The built-in theme. Every slot is populated so rendering looks good with
    /// no configuration.
    public static let `default` = RillTheme(
        fonts: .default,
        colors: .default,
        metrics: .default,
        codeBlock: .inlineScrollable(maxPreviewLines: 16)
    )
}

extension RillTheme {
    /// The font set for each text role.
    ///
    /// Headings are addressable individually (``heading1`` … ``heading6``) and
    /// by level via ``heading(level:)``, which clamps out-of-range levels to the
    /// nearest valid heading so a malformed AST never traps.
    public struct Fonts: Sendable {
        /// The font for paragraph body text.
        public var body: Font
        /// The font for level-1 (largest) headings.
        public var heading1: Font
        /// The font for level-2 headings.
        public var heading2: Font
        /// The font for level-3 headings.
        public var heading3: Font
        /// The font for level-4 headings.
        public var heading4: Font
        /// The font for level-5 headings.
        public var heading5: Font
        /// The font for level-6 (smallest) headings.
        public var heading6: Font
        /// The monospaced font for inline and block code.
        public var code: Font
        /// The font for blockquote text.
        public var blockquote: Font
        /// The font for table cells.
        public var table: Font

        /// Creates a font set.
        public init(
            body: Font,
            heading1: Font,
            heading2: Font,
            heading3: Font,
            heading4: Font,
            heading5: Font,
            heading6: Font,
            code: Font,
            blockquote: Font,
            table: Font
        ) {
            self.body = body
            self.heading1 = heading1
            self.heading2 = heading2
            self.heading3 = heading3
            self.heading4 = heading4
            self.heading5 = heading5
            self.heading6 = heading6
            self.code = code
            self.blockquote = blockquote
            self.table = table
        }

        /// The heading font for a 1-based level, clamped to `1...6`.
        /// - Parameter level: The heading level; values below `1` clamp to
        ///   ``heading1`` and values above `6` clamp to ``heading6``.
        /// - Returns: The font for the (clamped) heading level.
        public func heading(level: Int) -> Font {
            switch min(max(level, 1), 6) {
            case 1: return heading1
            case 2: return heading2
            case 3: return heading3
            case 4: return heading4
            case 5: return heading5
            default: return heading6
            }
        }

        /// The built-in font set. Uses Dynamic Type text styles so the package
        /// respects the user's preferred content size out of the box, with a
        /// monospaced design for code.
        public static let `default` = Fonts(
            body: .body,
            heading1: .largeTitle.weight(.bold),
            heading2: .title.weight(.bold),
            heading3: .title2.weight(.semibold),
            heading4: .title3.weight(.semibold),
            heading5: .headline,
            heading6: .subheadline.weight(.semibold),
            code: .system(.callout, design: .monospaced),
            blockquote: .body.italic(),
            table: .callout
        )
    }

    /// The color set for each visual role.
    public struct Colors: Sendable {
        /// The primary text color for body and headings.
        public var textPrimary: Color
        /// The secondary text color for de-emphasized text (e.g. captions).
        public var textSecondary: Color
        /// The color of hyperlinks.
        public var link: Color
        /// The background fill behind code blocks and inline code.
        public var codeBackground: Color
        /// The color of the vertical bar drawn beside blockquotes.
        public var quoteBar: Color
        /// The accent color of citation pills.
        public var citation: Color
        /// The color of table grid lines and borders.
        public var tableBorder: Color
        /// The palette used by ``CodeHighlighter``s to color code tokens
        /// (keywords, strings, comments, numbers).
        public var syntax: SyntaxColors
        /// The accent palette for GitHub-style alert callouts, keyed by kind.
        public var alerts: AlertColors

        /// Creates a color set.
        ///
        /// - Parameters:
        ///   - syntax: The token palette used for syntax highlighting. Defaults
        ///     to ``SyntaxColors/default`` so existing callers need not supply one.
        ///   - alerts: The alert-callout accent palette. Defaults to
        ///     ``AlertColors/default`` so existing callers need not supply one.
        public init(
            textPrimary: Color,
            textSecondary: Color,
            link: Color,
            codeBackground: Color,
            quoteBar: Color,
            citation: Color,
            tableBorder: Color,
            syntax: SyntaxColors = .default,
            alerts: AlertColors = .default
        ) {
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.link = link
            self.codeBackground = codeBackground
            self.quoteBar = quoteBar
            self.citation = citation
            self.tableBorder = tableBorder
            self.syntax = syntax
            self.alerts = alerts
        }

        /// The built-in color set. Uses system semantic colors so it adapts to
        /// light and dark appearances automatically.
        public static let `default` = Colors(
            textPrimary: .primary,
            textSecondary: .secondary,
            link: .accentColor,
            codeBackground: Color.gray.opacity(0.12),
            quoteBar: .secondary,
            citation: .accentColor,
            tableBorder: Color.gray.opacity(0.3),
            syntax: .default,
            alerts: .default
        )
    }

    /// The accent palette for GitHub-style alert callouts.
    ///
    /// Each ``AlertKind`` gets a single tint used for its icon, left border, and
    /// title; the callout background is derived by tinting that color at low
    /// opacity. The defaults mirror GitHub's NOTE/TIP/IMPORTANT/WARNING/CAUTION
    /// hues and read well over both light and dark backgrounds.
    public struct AlertColors: Sendable {
        /// The tint for `[!NOTE]` callouts.
        public var note: Color
        /// The tint for `[!TIP]` callouts.
        public var tip: Color
        /// The tint for `[!IMPORTANT]` callouts.
        public var important: Color
        /// The tint for `[!WARNING]` callouts.
        public var warning: Color
        /// The tint for `[!CAUTION]` callouts.
        public var caution: Color

        /// Creates an alert palette.
        public init(note: Color, tip: Color, important: Color, warning: Color, caution: Color) {
            self.note = note
            self.tip = tip
            self.important = important
            self.warning = warning
            self.caution = caution
        }

        /// The tint for a given alert kind.
        /// - Parameter kind: The alert kind to color.
        /// - Returns: The accent color for that kind.
        public func tint(for kind: AlertKind) -> Color {
            switch kind {
            case .note: return note
            case .tip: return tip
            case .important: return important
            case .warning: return warning
            case .caution: return caution
            }
        }

        /// The built-in alert palette, mirroring GitHub's alert hues.
        public static let `default` = AlertColors(
            note: Color(red: 0.03, green: 0.41, blue: 0.85),
            tip: Color(red: 0.10, green: 0.50, blue: 0.22),
            important: Color(red: 0.51, green: 0.29, blue: 0.87),
            warning: Color(red: 0.60, green: 0.40, blue: 0.0),
            caution: Color(red: 0.81, green: 0.13, blue: 0.18)
        )
    }

    /// The color palette used by ``CodeHighlighter``s to tint code tokens.
    ///
    /// Highlighting is deliberately coarse — a handful of token classes shared
    /// across every supported language — so the same palette colors Swift,
    /// JavaScript/TypeScript, Python, JSON, Bash, HTML, and Rust consistently.
    /// Untyped text falls back to ``plain``.
    public struct SyntaxColors: Sendable {
        /// The color for language keywords (e.g. `func`, `const`, `def`, `fn`)
        /// and, for markup, tag names. Reused for boolean/null literals.
        public var keyword: Color
        /// The color for string and character literals.
        public var string: Color
        /// The color for line and block comments.
        public var comment: Color
        /// The color for numeric literals.
        public var number: Color
        /// The color for ordinary, unclassified text (identifiers, punctuation).
        public var plain: Color

        /// Creates a syntax palette.
        /// - Parameters:
        ///   - keyword: The keyword/tag color.
        ///   - string: The string-literal color.
        ///   - comment: The comment color.
        ///   - number: The numeric-literal color.
        ///   - plain: The fallback color for unclassified text.
        public init(
            keyword: Color,
            string: Color,
            comment: Color,
            number: Color,
            plain: Color
        ) {
            self.keyword = keyword
            self.string = string
            self.comment = comment
            self.number = number
            self.plain = plain
        }

        /// The built-in syntax palette. Uses fixed hues that read well over the
        /// default code background in both light and dark appearances, with
        /// ``plain`` deferring to the theme's primary text color.
        public static let `default` = SyntaxColors(
            keyword: Color(red: 0.66, green: 0.20, blue: 0.62),
            string: Color(red: 0.77, green: 0.18, blue: 0.13),
            comment: Color(red: 0.42, green: 0.47, blue: 0.53),
            number: Color(red: 0.12, green: 0.31, blue: 0.78),
            plain: .primary
        )
    }

    /// The layout metrics for spacing, indentation, padding, and corners.
    ///
    /// All values are in points.
    public struct Metrics: Sendable {
        /// The vertical spacing inserted between block-level elements.
        public var paragraphSpacing: CGFloat
        /// The horizontal indentation applied per nested list level.
        public var listIndent: CGFloat
        /// The padding inside bordered/filled blocks such as blockquotes and
        /// tables.
        public var blockPadding: CGFloat
        /// The padding inside code blocks.
        public var codePadding: CGFloat
        /// The corner radius applied to general bordered blocks.
        public var cornerRadius: CGFloat
        /// The corner radius applied to code blocks.
        public var codeCornerRadius: CGFloat

        /// Creates a metrics set.
        public init(
            paragraphSpacing: CGFloat,
            listIndent: CGFloat,
            blockPadding: CGFloat,
            codePadding: CGFloat,
            cornerRadius: CGFloat,
            codeCornerRadius: CGFloat
        ) {
            self.paragraphSpacing = paragraphSpacing
            self.listIndent = listIndent
            self.blockPadding = blockPadding
            self.codePadding = codePadding
            self.cornerRadius = cornerRadius
            self.codeCornerRadius = codeCornerRadius
        }

        /// The built-in metrics, tuned for comfortable reading of streamed AI
        /// responses.
        public static let `default` = Metrics(
            paragraphSpacing: 12,
            listIndent: 20,
            blockPadding: 12,
            codePadding: 12,
            cornerRadius: 8,
            codeCornerRadius: 10
        )
    }
}
