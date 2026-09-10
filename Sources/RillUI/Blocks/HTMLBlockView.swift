import SwiftUI
import RillCore

/// Renders a raw ``HTMLBlock`` as escaped, monospaced text.
///
/// Per the v1 non-goal, raw HTML is *not* interpreted; the markup is shown
/// verbatim so the reader sees exactly what the model emitted, with no risk of
/// executing or mis-rendering it.
struct HTMLBlockView: View {
    /// The HTML block to render.
    let html: HTMLBlock

    /// The visual theme.
    let theme: RillTheme

    var body: some View {
        let model = Model(html: html)
        Text(model.escapedText)
            .font(theme.fonts.code)
            .foregroundStyle(theme.colors.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The render-independent view model for a raw HTML block. Exposed for
    /// headless assertions.
    struct Model {
        /// The raw markup, shown verbatim as escaped text.
        let escapedText: String

        /// Always `true` in v1: HTML is rendered as plain text, not interpreted.
        let isRenderedAsPlainText = true

        /// Builds an HTML-block model from its block.
        init(html: HTMLBlock) {
            self.escapedText = html.raw
        }
    }
}
