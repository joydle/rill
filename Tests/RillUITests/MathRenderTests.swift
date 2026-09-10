import XCTest
import SwiftUI
@testable import RillUI
import RillMath

/// Tests for the RillUI math views (`MathView` / `MathBoxRenderer`).
///
/// These run headlessly: they assert on the laid-out ``MathBox`` size, on the
/// view model the math view derives, and that the view builds without trapping.
/// There are NO pixel snapshots — the box geometry and view initialization are
/// the contract, not rendered output.
@MainActor
final class MathRenderTests: XCTestCase {

    // MARK: - Box layout is non-empty for real equations

    /// Every supported construct must lay out to a ``MathBox`` with non-zero
    /// width and a non-zero vertical extent (`height + depth`). A blank box would
    /// render an invisible equation, violating the never-blank contract.
    func testLaidOutBoxIsNonZeroForEverySupportedConstruct() {
        let cases: [String] = [
            "\\frac{a}{b}",
            "\\sqrt{x}",
            "\\sqrt[3]{x}",
            "\\sum_{i=0}^{n} i",
            "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}",
        ]
        for latex in cases {
            let model = MathView.Model(latex: latex, style: .display, theme: .default)
            XCTAssertGreaterThan(model.box.width, 0,
                                 "Width must be > 0 for \(latex)")
            XCTAssertGreaterThan(model.box.height + model.box.depth, 0,
                                 "Vertical extent must be > 0 for \(latex)")
            XCTAssertGreaterThan(model.pixelSize.width, 0,
                                 "Pixel width must be > 0 for \(latex)")
            XCTAssertGreaterThan(model.pixelSize.height, 0,
                                 "Pixel height must be > 0 for \(latex)")
        }
    }

    // MARK: - Each construct's view builds without trapping

    func testMathViewBuildsForFraction() {
        let view = MathView(latex: "\\frac{a}{b}", style: .display, theme: .default)
        _ = view.body
    }

    func testMathViewBuildsForSqrt() {
        let view = MathView(latex: "\\sqrt[3]{x+1}", style: .display, theme: .default)
        _ = view.body
    }

    func testMathViewBuildsForSumWithLimits() {
        let view = MathView(latex: "\\sum_{i=0}^{n} i", style: .display, theme: .default)
        _ = view.body
    }

    func testMathViewBuildsForPmatrix() {
        let view = MathView(
            latex: "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}",
            style: .display, theme: .default
        )
        _ = view.body
    }

    // MARK: - Graceful degradation: unknown command → literal escaped text

    /// An unmapped control sequence must not crash and must not blank the
    /// equation: the parser degrades it to ``MathNode/unknown(_:)`` and the view
    /// still lays it out to a visible, non-zero box carrying the command name as
    /// literal text.
    func testUnknownCommandFallsBackToLiteralTextWithoutCrashing() {
        let model = MathView.Model(latex: "\\notacommand", style: .text, theme: .default)
        // No crash, and a visible box.
        XCTAssertGreaterThan(model.box.width, 0)
        XCTAssertGreaterThan(model.box.height + model.box.depth, 0)
        // The fallback literal text preserves the command name.
        XCTAssertTrue(model.literalText.contains("notacommand"),
                      "Unknown command must surface as literal text, got \(model.literalText)")
        // The view still builds.
        let view = MathView(latex: "\\notacommand", style: .text, theme: .default)
        _ = view.body
    }

    // MARK: - Node-array initializer parity

    /// `MathView` accepts a pre-parsed node array as well as a latex string; both
    /// paths produce the same laid-out box for equivalent input.
    func testNodeArrayInitializerMatchesLatexInitializer() {
        let nodes = MathParser.parse("\\frac{a}{b}")
        let fromNodes = MathView.Model(nodes: nodes, style: .display, theme: .default)
        let fromLatex = MathView.Model(latex: "\\frac{a}{b}", style: .display, theme: .default)
        XCTAssertEqual(fromNodes.box, fromLatex.box)
    }

    // MARK: - Inline vs display style

    /// Inline and display styles must both lay out non-empty boxes; for an
    /// operator with limits the display box stacks limits (taller) while inline
    /// places them beside (wider), so the two boxes differ.
    func testInlineAndDisplayStylesDifferForBigOperatorLimits() {
        let display = MathView.Model(latex: "\\sum_{i=0}^{n} i", style: .display, theme: .default)
        let inline = MathView.Model(latex: "\\sum_{i=0}^{n} i", style: .text, theme: .default)
        XCTAssertGreaterThan(display.box.width, 0)
        XCTAssertGreaterThan(inline.box.width, 0)
        XCTAssertNotEqual(display.box, inline.box,
                          "Display (stacked limits) and inline (beside) must differ.")
    }

    // MARK: - Renderer drawing instructions are non-empty

    /// `MathBoxRenderer` flattens a laid-out box into absolute-positioned draw
    /// commands. A non-empty box must yield at least one draw command, proving the
    /// Canvas closure has something to paint (asserted on the command list, not on
    /// pixels).
    func testRendererProducesDrawCommandsForFraction() {
        let model = MathView.Model(latex: "\\frac{a}{b}", style: .display, theme: .default)
        let commands = MathBoxRenderer.drawCommands(
            for: model.box,
            color: .black
        )
        XCTAssertFalse(commands.isEmpty, "A fraction must produce draw commands.")
        // A fraction has a bar rule and glyphs.
        XCTAssertTrue(commands.contains { if case .rule = $0 { return true } else { return false } },
                      "A fraction must include the bar rule.")
        XCTAssertTrue(commands.contains { if case .glyph = $0 { return true } else { return false } },
                      "A fraction must include glyphs.")
    }
}
