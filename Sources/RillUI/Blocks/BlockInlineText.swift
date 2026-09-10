import SwiftUI
import RillCore

/// Thin internal adapter the block renderers use to lower inline content to
/// styled text and copy payloads.
///
/// The attributed-string styling lives in the public ``InlineRenderer`` (Task
/// 11); `BlockInlineText/attributed(_:theme:)` forwards to it (with
/// ``RenderConfig/default``) so block views keep their two-argument call sites
/// while there is a single source of truth for inline styling. The plain-text
/// flattener used for copy payloads and view-model assertions stays here.
enum BlockInlineText {

    /// Flattens inline content into a styled `AttributedString` via
    /// ``InlineRenderer``.
    /// - Parameters:
    ///   - inlines: The inline run to render.
    ///   - theme: The theme supplying link color and code styling.
    /// - Returns: A styled attributed string.
    static func attributed(_ inlines: [Inline], theme: RillTheme) -> AttributedString {
        InlineRenderer.attributed(inlines, theme: theme, config: .default)
    }

    /// The plain, unstyled text of an inline run (used for copy payloads and
    /// view-model assertions).
    static func plainText(_ inlines: [Inline]) -> String {
        var out = ""
        for inline in inlines { appendPlain(inline, into: &out) }
        return out
    }

    // MARK: - Plain-text lowering

    private static func appendPlain(_ inline: Inline, into out: inout String) {
        switch inline {
        case .text(let s): out += s
        case .softBreak: out += " "
        case .lineBreak: out += "\n"
        case .emphasis(let c), .strong(let c), .strikethrough(let c):
            for child in c { appendPlain(child, into: &out) }
        case .code(let s): out += s
        case .link(let link):
            for child in link.inlines { appendPlain(child, into: &out) }
        case .image(let image): out += image.alt.isEmpty ? image.url : image.alt
        case .mathInline(let latex): out += latex
        case .citation(let citation): out += "[\(citation.marker)]"
        case .rawHTML(let raw): out += raw
        }
    }
}
