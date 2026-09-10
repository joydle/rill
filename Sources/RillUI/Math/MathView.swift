import SwiftUI
import RillMath

/// Renders a LaTeX math expression as native SwiftUI, drawing a TeX-style box
/// layout with `Canvas` + CoreText glyphs — no images, no bundled font atlas,
/// no `iosMath`.
///
/// `MathView` accepts either a raw `latex` string (which it parses via
/// ``MathParser``) or a pre-parsed `[MathNode]` array, lays it out with
/// ``MathLayout`` at the requested ``MathStyle``, and paints the resulting
/// ``MathBox`` through ``MathBoxRenderer``. Use ``MathStyle/display`` for
/// stand-alone equations (`$$ … $$`) and ``MathStyle/text`` for inline math
/// (`$ … $`): display stacks big-operator limits above/below while inline places
/// them beside.
///
/// Graceful degradation is inherited from the parser/layout stages: an unmapped
/// command degrades to ``MathNode/unknown(_:)`` and renders as literal escaped
/// text, so a streamed equation is never blank and never crashes.
public struct MathView: View {
    /// The render-independent layout model. Exposed for headless assertions: it
    /// carries the parsed nodes, the laid-out ``MathBox``, and the box's pixel
    /// size, all without touching the screen.
    public struct Model: Sendable {
        /// The parsed math node tree.
        public let nodes: [MathNode]
        /// The style the box was laid out at.
        public let style: MathStyle
        /// The laid-out TeX box tree.
        public let box: MathBox
        /// The frame size (in points) required to draw the box.
        public let pixelSize: CGSize
        /// The distance (in points) from the top of ``pixelSize`` down to the
        /// math reference baseline — i.e. the box's height above the baseline.
        /// A baseline-aware container (``FlowLayout``, an `HStack`) reads this so
        /// the math sits on the surrounding text baseline rather than being
        /// vertically centered or bottom-aligned.
        public let baseline: Double
        /// The literal text content of the expression, used as the accessibility
        /// label and the never-blank fallback for unmapped commands.
        public let literalText: String

        /// Builds a model from a pre-parsed node array.
        /// - Parameters:
        ///   - nodes: The parsed math nodes.
        ///   - style: The math style (display vs inline).
        ///   - theme: The visual theme (reserved for future font selection).
        public init(nodes: [MathNode], style: MathStyle, theme: RillTheme) {
            self.nodes = nodes
            self.style = style
            let laidOut = MathLayout.layout(nodes, style: style)
            self.box = laidOut
            self.pixelSize = MathBoxRenderer.size(of: laidOut)
            self.baseline = laidOut.height
            self.literalText = Model.literal(of: nodes)
        }

        /// Builds a model by parsing a LaTeX string.
        /// - Parameters:
        ///   - latex: The LaTeX fragment (without surrounding `$`/`$$`).
        ///   - style: The math style (display vs inline).
        ///   - theme: The visual theme.
        public init(latex: String, style: MathStyle, theme: RillTheme) {
            self.init(nodes: MathParser.parse(latex), style: style, theme: theme)
        }

        /// Flattens a node tree into its plain literal text (for accessibility
        /// and degradation), preserving unmapped command names.
        static func literal(of nodes: [MathNode]) -> String {
            nodes.map(literal(of:)).joined()
        }

        private static func literal(of node: MathNode) -> String {
            switch node {
            case .symbol(let s): return s
            case .text(let s): return s
            case .unknown(let name): return "\\" + name
            case .space: return " "
            case .group(let body): return literal(of: body)
            case .frac(let num, let den):
                return literal(of: num) + "/" + literal(of: den)
            case .sqrt(let index, let radicand):
                let idx = index.map { "[" + literal(of: $0) + "]" } ?? ""
                return "\u{221A}" + idx + literal(of: radicand)
            case .scripts(let base, let sup, let sub):
                var out = literal(of: base)
                if let sub { out += "_" + literal(of: sub) }
                if let sup { out += "^" + literal(of: sup) }
                return out
            case .bigOp(let op, let lower, let upper):
                var out = op
                if let lower { out += "_" + literal(of: lower) }
                if let upper { out += "^" + literal(of: upper) }
                return out
            case .delimited(let left, let right, let body):
                let l = left == "." ? "" : left
                let r = right == "." ? "" : right
                return l + literal(of: body) + r
            case .matrix(_, let rows):
                return rows.map { row in
                    row.map { literal(of: $0) }.joined(separator: " ")
                }.joined(separator: "; ")
            case .accent(_, let base):
                return literal(of: base)
            }
        }
    }

    /// The layout model driving the draw.
    public let model: Model
    /// The visual theme (supplies the glyph color and code font).
    public let theme: RillTheme

    /// Creates a math view from a pre-parsed node array.
    /// - Parameters:
    ///   - nodes: The parsed ``MathNode`` array.
    ///   - style: The math style; ``MathStyle/display`` for block equations,
    ///     ``MathStyle/text`` for inline.
    ///   - theme: The visual theme.
    public init(nodes: [MathNode], style: MathStyle, theme: RillTheme = .default) {
        self.model = Model(nodes: nodes, style: style, theme: theme)
        self.theme = theme
    }

    /// Creates a math view by parsing a LaTeX string.
    /// - Parameters:
    ///   - latex: The LaTeX fragment (without surrounding `$`/`$$`).
    ///   - style: The math style; ``MathStyle/display`` for block equations,
    ///     ``MathStyle/text`` for inline.
    ///   - theme: The visual theme.
    public init(latex: String, style: MathStyle, theme: RillTheme = .default) {
        self.model = Model(latex: latex, style: style, theme: theme)
        self.theme = theme
    }

    /// Draws the laid-out math box into a `Canvas` sized to the box metrics.
    public var body: some View {
        let size = model.pixelSize
        let color = theme.colors.textPrimary
        let box = model.box
        Canvas { context, _ in
            let commands = MathBoxRenderer.drawCommands(for: box, color: color)
            for command in commands {
                switch command {
                case .glyph(let text, let x, let baseline, let scriptLevel):
                    let fontSize = MathStyle.baseFontSize * MathView.shrink(for: scriptLevel)
                    var resolved = context.resolve(
                        Text(text).font(.system(size: fontSize)).foregroundColor(color)
                    )
                    let measured = resolved.measure(
                        in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
                    )
                    resolved.shading = .color(color)
                    // CoreText/Canvas draws text from its top-left; convert the
                    // baseline to a top by subtracting the text's ascent
                    // (approximated as most of the measured line height).
                    let top = baseline - measured.height * 0.78
                    context.draw(resolved, at: CGPoint(x: x, y: top), anchor: .topLeading)

                case .rule(let x, let y, let width, let height):
                    let rect = CGRect(x: x, y: y, width: width, height: height)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        // Report the true math baseline so baseline-aligned containers place the
        // box on the surrounding text baseline. Without this SwiftUI treats a
        // non-Text view's text baseline as its frame bottom, sinking the math by
        // its full depth below the line.
        .alignmentGuide(.firstTextBaseline) { _ in CGFloat(model.baseline) }
        .alignmentGuide(.lastTextBaseline) { _ in CGFloat(model.baseline) }
        .accessibilityLabel(model.literalText)
    }

    /// The font shrink factor for a script level, matching ``MathStyle``'s
    /// `scriptPercentScaleDown` chain (0 → 1, 1 → 0.7, 2+ → 0.5).
    static func shrink(for scriptLevel: Int) -> Double {
        switch scriptLevel {
        case ...0: return 1.0
        case 1: return 0.7
        default: return 0.5
        }
    }
}
