import SwiftUI
import RillCore

/// Renders a display ``MathBlock`` (`$$ … $$` / `\[ … \]`).
///
/// The block parses its LaTeX and draws a native TeX-style box layout via
/// ``MathView`` in ``MathStyle/display`` (stacked operator limits, full-size
/// fractions). An unmapped command degrades to literal escaped text inside the
/// same view, so a streamed equation is never blank and never crashes. The
/// view-model still exposes the raw LaTeX (`fallbackText`) for headless
/// assertions and host introspection.
struct MathBlockView: View {
    /// The math block to render.
    let mathBlock: MathBlock

    /// The visual theme.
    let theme: RillTheme

    var body: some View {
        MathView(latex: mathBlock.latex, style: .display, theme: theme)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, theme.metrics.paragraphSpacing / 2)
    }

    /// The render-independent view model for a math block. Exposed for headless
    /// assertions and as the contract the math views build on.
    struct Model {
        /// The raw LaTeX body.
        let latex: String
        /// Whether the block's closing delimiter has arrived.
        let isClosed: Bool
        /// The literal text, used as the accessibility label and the never-blank fallback for an expression the glyph renderer cannot lay out:
        /// the raw LaTeX, so a streamed equation is never blank.
        let fallbackText: String

        /// Builds a math-block model from its block and theme.
        init(mathBlock: MathBlock, theme: RillTheme) {
            self.latex = mathBlock.latex
            self.isClosed = mathBlock.isClosed
            self.fallbackText = mathBlock.latex
        }
    }
}
