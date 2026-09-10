@testable import RillMath

/// Test-only utilities that walk a ``MathBox`` tree and extract measurable
/// geometry (rule positions, script boxes, column x-positions). Kept in the test
/// target so production code carries no inspection scaffolding.
enum MathLayoutInspector {

    /// Geometry of a fraction in vbox coordinates (y grows downward from top).
    struct FractionGeometry {
        let numeratorBottom: Double
        let barY: Double
        let denominatorTop: Double
    }

    /// Geometry of a radical: the overbar rule y and the radicand top.
    struct SqrtGeometry {
        let ruleY: Double
        let radicandTop: Double
        let ruleThickness: Double
    }

    /// Geometry of a stacked big operator.
    struct BigOpGeometry {
        let upperY: Double
        let operatorY: Double
        let lowerY: Double
    }

    // MARK: First-rule

    /// Returns the first ``Rule`` found anywhere in the tree.
    static func firstRule(in box: MathBox) -> Rule? {
        switch box {
        case .rule(let r): return r
        case .hbox(let h): return h.children.lazy.compactMap { firstRule(in: $0.box) }.first
        case .vbox(let v): return v.children.lazy.compactMap { firstRule(in: $0.box) }.first
        case .glyph, .glue: return nil
        }
    }

    // MARK: Fraction

    /// Finds the first fraction-shaped vbox (num, rule, den) and reports the
    /// numerator's bottom edge, the bar's y, and the denominator's top edge, all
    /// in that vbox's top-down coordinate space.
    static func fractionGeometry(in box: MathBox) -> FractionGeometry? {
        if case .vbox(let v) = box, v.children.count == 3,
           case .rule = v.children[1].box {
            let num = v.children[0]
            let rule = v.children[1]
            let den = v.children[2]
            // numerator bottom = its baseline (yOffset) + its depth.
            let numBottom = num.yOffset + num.box.depth
            // denominator top = its baseline (yOffset) - its height.
            let denTop = den.yOffset - den.box.height
            return FractionGeometry(
                numeratorBottom: numBottom,
                barY: rule.yOffset,
                denominatorTop: denTop)
        }
        // Recurse.
        for child in children(of: box) {
            if let geo = fractionGeometry(in: child) { return geo }
        }
        return nil
    }

    // MARK: Scripts

    /// Returns the smaller (script-level > 0) sub-box of a scripts hbox.
    static func scriptBox(in box: MathBox) -> MathBox? {
        if case .hbox(let h) = box {
            // The base is child 0 at level 0; a script is a later child at a
            // higher script level or with a nonzero yOffset.
            for child in h.children.dropFirst() {
                if child.box.scriptLevel > 0 { return child.box }
                if child.yOffset != 0 { return child.box }
            }
        }
        for child in children(of: box) {
            if let s = scriptBox(in: child) { return s }
        }
        return nil
    }

    // MARK: Sqrt

    /// Finds the radical's over-rule vbox and reports the rule y and radicand top.
    static func sqrtGeometry(in box: MathBox) -> SqrtGeometry? {
        if case .vbox(let v) = box, v.children.count == 2,
           case .rule(let r) = v.children[0].box {
            let rule = v.children[0]
            let body = v.children[1]
            let radicandTop = body.yOffset - body.box.height
            return SqrtGeometry(
                ruleY: rule.yOffset,
                radicandTop: radicandTop,
                ruleThickness: r.height + r.depth)
        }
        for child in children(of: box) {
            if let geo = sqrtGeometry(in: child) { return geo }
        }
        return nil
    }

    // MARK: Big operator

    /// Finds a stacked big-op vbox (upper, operator, lower) and reports each
    /// child's y.
    static func bigOpGeometry(in box: MathBox) -> BigOpGeometry? {
        if case .vbox(let v) = box, v.children.count == 3 {
            // Middle child is the operator glyph.
            if case .glyph = v.children[1].box {
                return BigOpGeometry(
                    upperY: v.children[0].yOffset,
                    operatorY: v.children[1].yOffset,
                    lowerY: v.children[2].yOffset)
            }
        }
        for child in children(of: box) {
            if let geo = bigOpGeometry(in: child) { return geo }
        }
        return nil
    }

    // MARK: Matrix

    /// Returns per-column absolute x-positions across all matrix rows. The result
    /// is indexed `[column][row]`.
    static func matrixColumnXPositions(in box: MathBox) -> [[Double]] {
        // Find the grid vbox: a vbox whose children are row hboxes.
        guard let grid = findGridVBox(in: box) else { return [] }
        var columns: [[Double]] = []
        for rowPlacement in grid.children {
            guard case .hbox(let rowBox) = rowPlacement.box else { continue }
            for (c, cell) in rowBox.children.enumerated() {
                if columns.count <= c { columns.append([]) }
                // Absolute x = row hbox xOffset + cell xOffset.
                columns[c].append(rowPlacement.xOffset + cell.xOffset)
            }
        }
        return columns
    }

    private static func findGridVBox(in box: MathBox) -> VBox? {
        if case .vbox(let v) = box {
            let allRowsAreHBoxes = !v.children.isEmpty && v.children.allSatisfy {
                if case .hbox = $0.box { return true }
                return false
            }
            if allRowsAreHBoxes { return v }
        }
        for child in children(of: box) {
            if let g = findGridVBox(in: child) { return g }
        }
        return nil
    }

    // MARK: Glyph search

    /// Whether a glyph with the given string appears anywhere in the tree.
    static func containsGlyph(_ s: String, in box: MathBox) -> Bool {
        if case .glyph(let g) = box, g.glyph == s { return true }
        for child in children(of: box) {
            if containsGlyph(s, in: child) { return true }
        }
        return false
    }

    /// The maximum drawn height (height + depth) of any glyph matching a
    /// delimiter character.
    static func maxDelimiterHeight(in box: MathBox) -> Double {
        var maxH = 0.0
        let delimiters: Set<String> = ["(", ")", "[", "]", "{", "}", "|", "\u{2016}"]
        func walk(_ b: MathBox) {
            if case .glyph(let g) = b, delimiters.contains(g.glyph) {
                maxH = max(maxH, g.height + g.depth)
            }
            for c in children(of: b) { walk(c) }
        }
        walk(box)
        return maxH
    }

    // MARK: Traversal

    private static func children(of box: MathBox) -> [MathBox] {
        switch box {
        case .hbox(let h): return h.children.map(\.box)
        case .vbox(let v): return v.children.map(\.box)
        case .glyph, .rule, .glue: return []
        }
    }
}
