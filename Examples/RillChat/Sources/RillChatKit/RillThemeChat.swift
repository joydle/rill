import SwiftUI
import RillUI

public extension RillTheme {
    /// Builds a fully-explicit `RillTheme` from a ``Palette`` so streamed answers
    /// read cleanly on any appearance. Demonstrates the theming surface: fonts,
    /// the full color set, a syntax palette, and metrics.
    static func chat(_ p: Palette, rounded: Bool = false) -> RillTheme {
        let d: Font.Design = rounded ? .rounded : .default
        let dark = p.scheme == .dark
        var t = RillTheme.default
        t.fonts = RillTheme.Fonts(
            body: .system(.callout, design: d),
            heading1: .system(.title2, design: d).weight(.bold),
            heading2: .system(.title3, design: d).weight(.bold),
            heading3: .system(.headline, design: d),
            heading4: .system(.subheadline, design: d).weight(.semibold),
            heading5: .system(.subheadline, design: d).weight(.semibold),
            heading6: .system(.footnote, design: d).weight(.semibold),
            code: .system(.caption, design: .monospaced),
            blockquote: .system(.callout, design: d).italic(),
            table: .system(.footnote, design: d))
        t.colors = RillTheme.Colors(
            textPrimary: p.ink, textSecondary: p.ink2, link: p.accent,
            codeBackground: p.codeBG, quoteBar: p.accent.opacity(0.55), citation: p.accent,
            tableBorder: p.border,
            syntax: RillTheme.SyntaxColors(
                keyword: dark ? c(0.80, 0.62, 1.0) : c(0.51, 0.22, 0.72),
                string:  dark ? c(0.52, 0.86, 0.66) : c(0.14, 0.52, 0.30),
                comment: p.ink2,
                number:  dark ? c(0.55, 0.78, 1.0) : c(0.13, 0.35, 0.82),
                plain: p.ink),
            alerts: .default)
        t.metrics.paragraphSpacing = 10
        t.metrics.codeCornerRadius = 12
        return t
    }
}
