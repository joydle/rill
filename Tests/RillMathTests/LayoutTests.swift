import XCTest
@testable import RillMath

/// Layout-metric tests for the TeX-style box layout engine. These assert on
/// measurable positions and sizes (never pixels): fraction-bar placement,
/// script shrink, sqrt rule position, matrix column alignment, and the
/// display-vs-text limit-placement difference.
final class LayoutTests: XCTestCase {

    // MARK: Style

    func testStyleScriptLevelsIncrease() {
        XCTAssertEqual(MathStyle.display.scriptLevel, 0)
        XCTAssertEqual(MathStyle.text.scriptLevel, 0)
        XCTAssertEqual(MathStyle.script.scriptLevel, 1)
        XCTAssertEqual(MathStyle.scriptScript.scriptLevel, 2)
    }

    func testScriptStyleFontSmallerThanText() {
        XCTAssertLessThan(MathStyle.script.fontSize, MathStyle.text.fontSize)
        XCTAssertLessThan(MathStyle.scriptScript.fontSize, MathStyle.script.fontSize)
    }

    func testStyleSuperscriptTransition() {
        // display/text both go to .script for their first-level scripts.
        XCTAssertEqual(MathStyle.display.superStyle.scriptLevel, 1)
        XCTAssertEqual(MathStyle.text.superStyle.scriptLevel, 1)
        // a script-style base's scripts shrink further.
        XCTAssertEqual(MathStyle.script.superStyle.scriptLevel, 2)
        // scriptScript is the floor.
        XCTAssertEqual(MathStyle.scriptScript.superStyle.scriptLevel, 2)
    }

    // MARK: Basic boxes

    func testSingleSymbolHasPositiveExtent() {
        let box = MathLayout.layout([.symbol("x")], style: .text)
        XCTAssertGreaterThan(box.width, 0)
        XCTAssertGreaterThan(box.height, 0)
        XCTAssertEqual(box.scriptLevel, 0)
    }

    func testHBoxWidthIsSumOfChildren() {
        let one = MathLayout.layout([.symbol("a")], style: .text)
        let three = MathLayout.layout([.symbol("a"), .symbol("b"), .symbol("c")], style: .text)
        // Three glyphs should be meaningfully wider than one.
        XCTAssertGreaterThan(three.width, one.width)
    }

    // MARK: Fraction

    func testFractionBarBetweenNumeratorDepthAndDenominatorHeight() {
        let frac = MathNode.frac(numerator: [.symbol("a")], denominator: [.symbol("b")])
        let box = MathLayout.layout([frac], style: .display)

        guard let rule = MathLayoutInspector.firstRule(in: box) else {
            return XCTFail("fraction must contain a rule")
        }
        // The numerator sits above the bar; its lowest point (baseline of the
        // overall frac box minus the rule's y) must be above the rule, and the
        // denominator below. We assert the rule's y is strictly between the
        // numerator's bottom and the denominator's top in the frac box's
        // coordinate space.
        let layout = MathLayoutInspector.fractionGeometry(in: box)
        guard let geo = layout else {
            return XCTFail("expected a fraction VBox")
        }
        // numeratorBottom is the y of the lowest numerator pixel; denominatorTop
        // is the y of the highest denominator pixel; the bar y must lie between.
        XCTAssertGreaterThan(geo.barY, geo.numeratorBottom)
        XCTAssertLessThan(geo.barY, geo.denominatorTop)
        XCTAssertGreaterThan(rule.height, 0)
    }

    func testFractionAxisCentering() {
        // The bar should be centered on the math axis: the frac box's height
        // (above baseline) and depth (below) straddle the axis so that the bar
        // is roughly axisHeight above the baseline.
        let frac = MathNode.frac(numerator: [.symbol("1")], denominator: [.symbol("2")])
        let box = MathLayout.layout([frac], style: .display)
        XCTAssertGreaterThan(box.height, 0)
        XCTAssertGreaterThan(box.depth, 0)
        let metrics = MathMetrics(fontSize: MathStyle.display.fontSize)
        // The bar (axis) is above the baseline by ~axisHeight; the whole box must
        // be tall enough to contain numerator above the axis.
        XCTAssertGreaterThan(box.height, metrics.axisHeight)
    }

    // MARK: Scripts

    func testSuperscriptBoxSmallerThanBase() {
        let scripts = MathNode.scripts(base: [.symbol("x")], sup: [.symbol("2")], sub: nil)
        let box = MathLayout.layout([scripts], style: .text)

        let baseBox = MathLayout.layout([.symbol("x")], style: .text)
        guard let scriptBox = MathLayoutInspector.scriptBox(in: box) else {
            return XCTFail("expected a script sub-box")
        }
        // The "2" laid out at script level must be shorter than an "x" at text level.
        XCTAssertLessThan(scriptBox.height, baseBox.height + baseBox.depth)
        XCTAssertEqual(scriptBox.scriptLevel, 1)
    }

    func testSuperscriptRaisedAboveBaseline() {
        let scripts = MathNode.scripts(base: [.symbol("x")], sup: [.symbol("2")], sub: nil)
        let box = MathLayout.layout([scripts], style: .text)
        // With a superscript, the composite box must be taller than the bare base
        // (the raised script adds height above the baseline).
        let baseBox = MathLayout.layout([.symbol("x")], style: .text)
        XCTAssertGreaterThan(box.height, baseBox.height)
    }

    func testSubscriptLowersBelowBaseline() {
        let scripts = MathNode.scripts(base: [.symbol("x")], sup: nil, sub: [.symbol("i")])
        let box = MathLayout.layout([scripts], style: .text)
        let baseBox = MathLayout.layout([.symbol("x")], style: .text)
        // A subscript pushes depth below the baseline.
        XCTAssertGreaterThan(box.depth, baseBox.depth)
    }

    // MARK: Sqrt

    func testSqrtRuleSitsAboveContent() {
        let sqrt = MathNode.sqrt(index: nil, radicand: [.symbol("x")])
        let box = MathLayout.layout([sqrt], style: .text)
        guard let geo = MathLayoutInspector.sqrtGeometry(in: box) else {
            return XCTFail("expected a sqrt VBox with an overbar rule")
        }
        // The overbar rule's top must be above (smaller y) the radicand content's top.
        XCTAssertLessThan(geo.ruleY, geo.radicandTop)
        XCTAssertGreaterThan(geo.ruleThickness, 0)
    }

    // MARK: Big operators — display vs text limit placement

    func testDisplayLimitsStackedTextLimitsBeside() {
        let op = MathNode.bigOp(op: "\u{2211}", lower: [.symbol("i")], upper: [.symbol("n")])

        let displayBox = MathLayout.layout([op], style: .display)
        let textBox = MathLayout.layout([op], style: .text)

        // Display style stacks limits above/below → the box is tall and narrow.
        // Text style places them beside → the box is short and wide.
        // Therefore the display box must be taller than the text box, and the
        // text box wider than the display box.
        XCTAssertGreaterThan(displayBox.height + displayBox.depth, textBox.height + textBox.depth)
        XCTAssertGreaterThan(textBox.width, displayBox.width)
    }

    func testDisplayLimitPlacementHasUpperAboveAndLowerBelow() {
        let op = MathNode.bigOp(op: "\u{2211}", lower: [.symbol("i")], upper: [.symbol("n")])
        let box = MathLayout.layout([op], style: .display)
        guard let geo = MathLayoutInspector.bigOpGeometry(in: box) else {
            return XCTFail("expected a stacked big-op VBox in display style")
        }
        // Upper limit above the operator, lower limit below.
        XCTAssertLessThan(geo.upperY, geo.operatorY)
        XCTAssertGreaterThan(geo.lowerY, geo.operatorY)
    }

    // MARK: Matrix column alignment

    func testMatrixColumnsAreXAligned() {
        // pmatrix with two rows, two columns. Column 0 cells must share an
        // x-origin; column 1 cells must share an x-origin.
        let rows: [[[MathNode]]] = [
            [[.symbol("a")], [.symbol("b")]],
            [[.symbol("c")], [.symbol("d")]],
        ]
        let matrix = MathNode.matrix(env: "pmatrix", rows: rows)
        let box = MathLayout.layout([matrix], style: .text)

        let cols = MathLayoutInspector.matrixColumnXPositions(in: box)
        XCTAssertEqual(cols.count, 2, "expected two columns of x-positions")
        for column in cols {
            guard let first = column.first else { continue }
            for x in column {
                XCTAssertEqual(x, first, accuracy: 0.001, "column cells must align in x")
            }
        }
        // The two columns must be at distinct x positions.
        if cols.count == 2, let c0 = cols[0].first, let c1 = cols[1].first {
            XCTAssertNotEqual(c0, c1)
        }
    }

    func testPmatrixHasDelimiters() {
        let rows: [[[MathNode]]] = [[[.symbol("a")]], [[.symbol("b")]]]
        let matrix = MathNode.matrix(env: "pmatrix", rows: rows)
        let box = MathLayout.layout([matrix], style: .text)
        // pmatrix is wrapped in parentheses → must contain delimiter glyphs.
        XCTAssertTrue(MathLayoutInspector.containsGlyph("(", in: box))
        XCTAssertTrue(MathLayoutInspector.containsGlyph(")", in: box))
    }

    // MARK: Delimiters auto-size to body

    func testDelimitersAutoSizeToBodyHeight() {
        let smallBody: [MathNode] = [.symbol("x")]
        let tallBody: [MathNode] = [.frac(numerator: [.symbol("a")], denominator: [.symbol("b")])]

        let small = MathLayout.layout(
            [.delimited(left: "(", right: ")", body: smallBody)], style: .display)
        let tall = MathLayout.layout(
            [.delimited(left: "(", right: ")", body: tallBody)], style: .display)

        let smallDelim = MathLayoutInspector.maxDelimiterHeight(in: small)
        let tallDelim = MathLayoutInspector.maxDelimiterHeight(in: tall)
        XCTAssertGreaterThan(tallDelim, smallDelim, "delimiters grow with body height")
    }

    // MARK: Graceful degradation

    func testUnknownCommandLaysOutAsText() {
        let box = MathLayout.layout([.unknown("foobar")], style: .text)
        XCTAssertGreaterThan(box.width, 0)
        // Should contain the literal text glyphs, not crash.
        XCTAssertTrue(MathLayoutInspector.containsGlyph("f", in: box))
    }

    func testEmptyInputProducesZeroWidthBox() {
        let box = MathLayout.layout([], style: .text)
        XCTAssertEqual(box.width, 0, accuracy: 0.0001)
    }
}
