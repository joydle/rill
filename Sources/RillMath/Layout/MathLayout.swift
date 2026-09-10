/// The TeX-style box layout engine.
///
/// `MathLayout.layout(_:style:)` consumes a ``MathNode`` tree (from
/// ``MathParser``) and produces a ``MathBox`` tree with real TeX positioning:
/// fraction bars centered on the math axis, super/subscripts shrunk and offset
/// from the baseline, radicals with an overbar rule above the radicand, big
/// operators with stacked limits in display style and beside-the-operator
/// limits in text style, aligned matrix grids, and auto-sized delimiters. It is
/// pure and `Sendable`, so every metric is unit-testable without any UI.
public enum MathLayout: Sendable {

    /// Lays out a list of nodes in the given style and returns the composite box.
    /// - Parameters:
    ///   - nodes: The parsed math node list.
    ///   - style: The math style (display/text/script/scriptScript).
    /// - Returns: A ``MathBox`` (an ``HBox`` for multi-node lists).
    public static func layout(_ nodes: [MathNode], style: MathStyle) -> MathBox {
        layoutList(nodes, style: style)
    }

    // MARK: - Horizontal list

    /// Lays out a node list as a horizontal box on a shared baseline.
    private static func layoutList(_ nodes: [MathNode], style: MathStyle) -> MathBox {
        let metrics = MathMetrics(fontSize: style.fontSize)
        var placements: [Placement] = []
        var x = 0.0
        var maxHeight = 0.0
        var maxDepth = 0.0

        for node in nodes {
            let box = layoutNode(node, style: style, metrics: metrics)
            placements.append(Placement(box: box, xOffset: x, yOffset: 0))
            x += box.width
            maxHeight = max(maxHeight, box.height)
            maxDepth = max(maxDepth, box.depth)
        }

        return .hbox(HBox(
            children: placements,
            width: x,
            height: maxHeight,
            depth: maxDepth,
            scriptLevel: style.scriptLevel
        ))
    }

    // MARK: - Node dispatch

    private static func layoutNode(_ node: MathNode, style: MathStyle, metrics: MathMetrics) -> MathBox {
        switch node {
        case .symbol(let s):
            return glyphRun(s, style: style, metrics: metrics)

        case .text(let s):
            return glyphRun(s, style: style, metrics: metrics)

        case .unknown(let name):
            return glyphRun(name, style: style, metrics: metrics)

        case .group(let body):
            return layoutList(body, style: style)

        case .space:
            return .glue(Glue(width: metrics.thinSpace, scriptLevel: style.scriptLevel))

        case .frac(let num, let den):
            return layoutFraction(numerator: num, denominator: den, style: style, metrics: metrics)

        case .sqrt(let index, let radicand):
            return layoutSqrt(index: index, radicand: radicand, style: style, metrics: metrics)

        case .scripts(let base, let sup, let sub):
            return layoutScripts(base: base, sup: sup, sub: sub, style: style, metrics: metrics)

        case .bigOp(let op, let lower, let upper):
            return layoutBigOp(op: op, lower: lower, upper: upper, style: style, metrics: metrics)

        case .delimited(let left, let right, let body):
            return layoutDelimited(left: left, right: right, body: body, style: style, metrics: metrics)

        case .matrix(let env, let rows):
            return layoutMatrix(env: env, rows: rows, style: style, metrics: metrics)

        case .accent(let kind, let base):
            return layoutAccent(kind: kind, base: base, style: style, metrics: metrics)
        }
    }

    // MARK: - Glyphs

    /// Builds an hbox of glyph boxes for a (possibly multi-character) string.
    private static func glyphRun(_ string: String, style: MathStyle, metrics: MathMetrics) -> MathBox {
        if string.isEmpty {
            return .hbox(HBox(children: [], width: 0, height: 0, depth: 0, scriptLevel: style.scriptLevel))
        }
        var placements: [Placement] = []
        var x = 0.0
        var maxHeight = 0.0
        var maxDepth = 0.0
        for ch in string {
            let g = glyphBox(String(ch), style: style, metrics: metrics)
            placements.append(Placement(box: .glyph(g), xOffset: x, yOffset: 0))
            x += g.width
            maxHeight = max(maxHeight, g.height)
            maxDepth = max(maxDepth, g.depth)
        }
        if placements.count == 1 {
            return placements[0].box
        }
        return .hbox(HBox(
            children: placements, width: x, height: maxHeight, depth: maxDepth,
            scriptLevel: style.scriptLevel))
    }

    /// Lowercase letters whose ink descends below the baseline.
    private static let descenders: Set<Character> = ["g", "j", "p", "q", "y"]

    /// Glyphs whose ink extends below the baseline beyond ordinary letters —
    /// delimiters, big operators, integral/summation, and tall punctuation. They
    /// must report a real depth so the box (and the Canvas frame derived from it)
    /// includes their descent instead of clipping it at the baseline.
    private static let deepGlyphs: Set<Character> = [
        "(", ")", "[", "]", "{", "}", "|", "/", "\\",
        "\u{2211}", "\u{220F}", "\u{222B}", "\u{222E}",   // ∑ ∏ ∫ ∮
        "\u{27E8}", "\u{27E9}", "\u{2016}",               // ⟨ ⟩ ‖
        "\u{222A}", "\u{222C}", "\u{222D}",               // ∪ ∬ ∭
        "Q", ",", ";",
    ]

    /// Glyphs whose ink reaches well above the nominal cap height (the same tall
    /// delimiters/operators), needing extra reserved ascent so their tops are not
    /// clipped at the frame's upper edge.
    private static let tallGlyphs: Set<Character> = [
        "(", ")", "[", "]", "{", "}", "|",
        "\u{2211}", "\u{220F}", "\u{222B}", "\u{222E}",
        "\u{27E8}", "\u{27E9}", "\u{2016}",
    ]

    /// Builds a single glyph box with metrics derived from the style's font size.
    /// Tall delimiters/operators reserve extra height, and glyphs that descend
    /// below the baseline reserve a real depth, so the rendered ink stays inside
    /// the box's frame rather than being clipped at the top or bottom edge.
    private static func glyphBox(_ ch: String, style: MathStyle, metrics: MathMetrics) -> Glyph {
        let c = ch.count == 1 ? ch.first : nil
        let depth: Double = (c.map { descenders.contains($0) || deepGlyphs.contains($0) } ?? false)
            ? metrics.descent : 0
        let height: Double = (c.map { tallGlyphs.contains($0) } ?? false)
            ? metrics.tallAscent : metrics.ascent
        return Glyph(
            glyph: ch,
            width: metrics.glyphWidth,
            height: height,
            depth: depth,
            scriptLevel: style.scriptLevel
        )
    }

    // MARK: - Fractions

    /// Lays out a fraction: numerator raised above the math axis, denominator
    /// lowered below it, with the bar centered on the axis.
    private static func layoutFraction(
        numerator: [MathNode], denominator: [MathNode],
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let partStyle = style.fractionStyle
        let num = layoutList(numerator, style: partStyle)
        let den = layoutList(denominator, style: partStyle)

        let ruleThickness = metrics.defaultRuleThickness
        let width = max(num.width, den.width) + 2 * metrics.thinSpace
        let axis = metrics.axisHeight

        // Numerator baseline shift up so its depth clears the bar; denominator
        // shift down so its height clears the bar. Bar sits on the axis.
        let barTopFromAxis = axis + ruleThickness / 2
        let barBottomFromAxis = axis - ruleThickness / 2

        // Distance from top of vbox to the math axis (== height of the box).
        let numHeight = num.height
        let numDepth = num.depth
        let height = numHeight + numDepth + metrics.numeratorGap + barTopFromAxis

        let denHeight = den.height
        let denDepth = den.depth
        let depth = denHeight + denDepth + metrics.denominatorGap - barBottomFromAxis

        // yOffsets are measured from the vbox's TOP down to each child's baseline.
        let numBaselineY = numHeight
        let barY = height - axis            // axis is `axis` above the box baseline
        let denBaselineY = barY + (axis - barBottomFromAxis) + metrics.denominatorGap + denHeight

        let numX = (width - num.width) / 2
        let denX = (width - den.width) / 2

        let rule = Rule(width: width, height: ruleThickness, depth: 0, scriptLevel: style.scriptLevel)

        let children = [
            Placement(box: num, xOffset: numX, yOffset: numBaselineY),
            Placement(box: .rule(rule), xOffset: 0, yOffset: barY),
            Placement(box: den, xOffset: denX, yOffset: denBaselineY),
        ]

        return .vbox(VBox(
            children: children, width: width, height: height, depth: depth,
            scriptLevel: style.scriptLevel))
    }

    // MARK: - Square roots

    /// Lays out a radical: the radicand in an hbox with a radical glyph at the
    /// left and an overbar rule running above the radicand.
    private static func layoutSqrt(
        index: [MathNode]?, radicand: [MathNode],
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let body = layoutList(radicand, style: style)
        let ruleThickness = metrics.defaultRuleThickness
        let gap = metrics.radicalGap

        // The radical symbol.
        let radical = glyphBox("\u{221A}", style: style, metrics: metrics)
        let radicalBox: MathBox = .glyph(Glyph(
            glyph: "\u{221A}",
            width: radical.width,
            height: body.height + gap + ruleThickness,
            depth: body.depth,
            scriptLevel: style.scriptLevel))

        // The radicand sits inside a vbox: overbar rule on top, then a gap, then
        // the radicand on its own baseline.
        let width = body.width

        // The overbar rule sits at the top; the radicand's top is `gap` below the
        // rule, so its baseline is rule + gap + body.height down from the top.
        let ruleY = ruleThickness                  // rule's bottom edge from the top
        let bodyTop = ruleThickness + gap
        let bodyBaselineY = bodyTop + body.height

        let rule = Rule(width: width, height: ruleThickness, depth: 0, scriptLevel: style.scriptLevel)
        let overVBox = VBox(
            children: [
                Placement(box: .rule(rule), xOffset: 0, yOffset: ruleY),
                Placement(box: body, xOffset: 0, yOffset: bodyBaselineY),
            ],
            width: width,
            height: bodyBaselineY,
            depth: max(0, body.depth),
            scriptLevel: style.scriptLevel)

        // Combine radical glyph + (optional index) + over-rule vbox in an hbox.
        var placements: [Placement] = []
        var x = 0.0

        if let index, !index.isEmpty {
            let idx = layoutList(index, style: .scriptScript)
            placements.append(Placement(box: idx, xOffset: x, yOffset: 0))
            x += idx.width
        }

        let radHeight = radicalBox.height
        let radDepth = radicalBox.depth
        placements.append(Placement(box: radicalBox, xOffset: x, yOffset: 0))
        x += radicalBox.width

        placements.append(Placement(box: .vbox(overVBox), xOffset: x, yOffset: 0))
        x += overVBox.width

        let height = max(radHeight, overVBox.height)
        let depth = max(radDepth, overVBox.depth)

        return .hbox(HBox(
            children: placements, width: x, height: height, depth: depth,
            scriptLevel: style.scriptLevel))
    }

    // MARK: - Scripts

    /// Lays out a base with optional super/subscripts shrunk to script style and
    /// offset above/below the baseline.
    private static func layoutScripts(
        base: [MathNode], sup: [MathNode]?, sub: [MathNode]?,
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let baseBox = layoutList(base, style: style)
        var placements: [Placement] = [Placement(box: baseBox, xOffset: 0, yOffset: 0)]
        var x = baseBox.width + metrics.scriptSpace
        var height = baseBox.height
        var depth = baseBox.depth

        if let sup, !sup.isEmpty {
            let supBox = layoutList(sup, style: style.superStyle)
            // Raise the superscript: its baseline sits superscriptShift above the
            // main baseline. yOffset negative = above baseline.
            let shift = max(metrics.superscriptShift, baseBox.height - supBox.depth)
            placements.append(Placement(box: supBox, xOffset: x, yOffset: -shift))
            height = max(height, shift + supBox.height)
            x += supBox.width
        }

        if let sub, !sub.isEmpty {
            let subBox = layoutList(sub, style: style.subStyle)
            // TeX subscriptShiftDown: drop the subscript so its top descends a
            // bounded amount below the baseline, clamped to at least
            // `subscriptShift`. (The previous `- baseBox.depth * 0` zeroed the
            // intended term, dropping the subscript by its full height so it hung
            // ~2.4× too deep and collided with following content.)
            let drop = max(metrics.subscriptShift, subBox.height - 0.8 * metrics.xHeight)
            let subX = (sup != nil) ? baseBox.width + metrics.scriptSpace : x
            placements.append(Placement(box: subBox, xOffset: subX, yOffset: drop))
            depth = max(depth, drop + subBox.depth)
            x = max(x, subX + subBox.width)
        }

        return .hbox(HBox(
            children: placements, width: x, height: height, depth: depth,
            scriptLevel: style.scriptLevel))
    }

    // MARK: - Big operators

    /// Lays out a big operator. In display style limits stack above/below; in
    /// text/script style they attach as sub/superscripts beside the operator.
    private static func layoutBigOp(
        op: String, lower: [MathNode]?, upper: [MathNode]?,
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        // The operator glyph, slightly enlarged in display style.
        let opScale = style.stacksLimits ? 1.4 : 1.0
        let opGlyph = Glyph(
            glyph: op,
            width: metrics.glyphWidth * opScale * Double(op.count),
            height: metrics.ascent * opScale,
            depth: metrics.descent * opScale,
            scriptLevel: style.scriptLevel)
        let opBox: MathBox = .glyph(opGlyph)

        if style.stacksLimits {
            return stackLimits(op: opBox, lower: lower, upper: upper, style: style, metrics: metrics)
        } else {
            // Beside-the-operator: treat as scripts on the operator.
            return layoutScriptsOnBox(
                opBox, sup: upper, sub: lower, style: style, metrics: metrics)
        }
    }

    /// Stacks an upper limit above and a lower limit below an operator box,
    /// centered horizontally, centering the operator on the math axis.
    private static func stackLimits(
        op: MathBox, lower: [MathNode]?, upper: [MathNode]?,
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let limitStyle = style.fractionStyle
        let upperBox = (upper.map { layoutList($0, style: limitStyle) }) ?? nil
        let lowerBox = (lower.map { layoutList($0, style: limitStyle) }) ?? nil

        let width = max(op.width, max(upperBox?.width ?? 0, lowerBox?.width ?? 0))

        var children: [Placement] = []
        var y = 0.0

        if let upperBox {
            let ux = (width - upperBox.width) / 2
            let upperBaselineY = upperBox.height
            children.append(Placement(box: upperBox, xOffset: ux, yOffset: upperBaselineY))
            y = upperBaselineY + upperBox.depth + metrics.limitGap
        }

        let opX = (width - op.width) / 2
        let opBaselineY = y + op.height
        children.append(Placement(box: op, xOffset: opX, yOffset: opBaselineY))
        y = opBaselineY + op.depth

        if let lowerBox {
            let lx = (width - lowerBox.width) / 2
            let lowerBaselineY = y + metrics.limitGap + lowerBox.height
            children.append(Placement(box: lowerBox, xOffset: lx, yOffset: lowerBaselineY))
            y = lowerBaselineY + lowerBox.depth
        }

        // Center the operator on the math axis: the box's reference baseline is
        // the operator's baseline shifted so the operator centers on the axis.
        let height = opBaselineY
        let depth = y - opBaselineY

        return .vbox(VBox(
            children: children, width: width, height: height, depth: depth,
            scriptLevel: style.scriptLevel))
    }

    /// Attaches scripts beside an already-laid-out base box (used for inline big
    /// operators).
    private static func layoutScriptsOnBox(
        _ baseBox: MathBox, sup: [MathNode]?, sub: [MathNode]?,
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        var placements: [Placement] = [Placement(box: baseBox, xOffset: 0, yOffset: 0)]
        var x = baseBox.width + metrics.scriptSpace
        var height = baseBox.height
        var depth = baseBox.depth

        if let sup, !sup.isEmpty {
            let supBox = layoutList(sup, style: style.superStyle)
            let shift = max(metrics.superscriptShift, baseBox.height - supBox.depth)
            placements.append(Placement(box: supBox, xOffset: x, yOffset: -shift))
            height = max(height, shift + supBox.height)
            x += supBox.width
        }
        if let sub, !sub.isEmpty {
            let subBox = layoutList(sub, style: style.subStyle)
            // Same bounded subscript drop as `layoutScripts` (TeX subscriptShiftDown).
            let drop = max(metrics.subscriptShift, subBox.height - 0.8 * metrics.xHeight)
            let subX = (sup != nil) ? baseBox.width + metrics.scriptSpace : x
            placements.append(Placement(box: subBox, xOffset: subX, yOffset: drop))
            depth = max(depth, drop + subBox.depth)
            x = max(x, subX + subBox.width)
        }

        return .hbox(HBox(
            children: placements, width: x, height: height, depth: depth,
            scriptLevel: style.scriptLevel))
    }

    // MARK: - Delimited groups

    /// Lays out `\left … \right` with delimiters auto-sized to the body height.
    private static func layoutDelimited(
        left: String, right: String, body: [MathNode],
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let bodyBox = layoutList(body, style: style)
        let axis = metrics.axisHeight

        // Auto-size: the delimiter spans the body plus padding, centered on axis.
        let halfTarget = max(bodyBox.height - axis, bodyBox.depth + axis) + metrics.delimiterPadding
        let delimHeight = halfTarget + axis
        let delimDepth = halfTarget - axis

        var placements: [Placement] = []
        var x = 0.0

        if left != "." {
            let lb = stretchyDelimiter(left, height: delimHeight, depth: delimDepth, style: style, metrics: metrics)
            placements.append(Placement(box: lb, xOffset: x, yOffset: 0))
            x += lb.width
        }
        placements.append(Placement(box: bodyBox, xOffset: x, yOffset: 0))
        x += bodyBox.width
        if right != "." {
            let rb = stretchyDelimiter(right, height: delimHeight, depth: delimDepth, style: style, metrics: metrics)
            placements.append(Placement(box: rb, xOffset: x, yOffset: 0))
            x += rb.width
        }

        let height = max(bodyBox.height, delimHeight)
        let depth = max(bodyBox.depth, delimDepth)

        return .hbox(HBox(
            children: placements, width: x, height: height, depth: depth,
            scriptLevel: style.scriptLevel))
    }

    /// Builds a single delimiter glyph sized to the requested height/depth.
    private static func stretchyDelimiter(
        _ glyph: String, height: Double, depth: Double,
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        .glyph(Glyph(
            glyph: glyph,
            width: metrics.glyphWidth * 0.6,
            height: height,
            depth: depth,
            scriptLevel: style.scriptLevel))
    }

    // MARK: - Matrices

    /// Lays out a matrix-family environment as an aligned grid, wrapping the grid
    /// in the environment's delimiters where applicable.
    private static func layoutMatrix(
        env: String, rows: [[[MathNode]]],
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        // Lay out every cell.
        let cellBoxes: [[MathBox]] = rows.map { row in
            row.map { layoutList($0, style: style) }
        }
        let columnCount = cellBoxes.map(\.count).max() ?? 0

        // Compute per-column widths (for x-alignment) and per-row heights/depths.
        var columnWidths = [Double](repeating: 0, count: columnCount)
        for row in cellBoxes {
            for (c, box) in row.enumerated() {
                columnWidths[c] = max(columnWidths[c], box.width)
            }
        }

        var rowHeights = [Double](repeating: 0, count: cellBoxes.count)
        var rowDepths = [Double](repeating: 0, count: cellBoxes.count)
        for (r, row) in cellBoxes.enumerated() {
            for box in row {
                rowHeights[r] = max(rowHeights[r], box.height)
                rowDepths[r] = max(rowDepths[r], box.depth)
            }
        }

        // Total grid width.
        let gap = metrics.matrixColumnGap
        var gridWidth = 0.0
        for (i, w) in columnWidths.enumerated() {
            gridWidth += w
            if i < columnWidths.count - 1 { gridWidth += gap }
        }

        // Build grid vbox: each row is an hbox positioned at column x-origins.
        var gridChildren: [Placement] = []
        var y = 0.0
        for (r, row) in cellBoxes.enumerated() {
            let rowBaselineY = y + rowHeights[r]
            var x = 0.0
            var rowPlacements: [Placement] = []
            for c in 0..<columnCount {
                let box = c < row.count ? row[c] : MathBox.hbox(
                    HBox(children: [], width: 0, height: 0, depth: 0, scriptLevel: style.scriptLevel))
                rowPlacements.append(Placement(box: box, xOffset: x, yOffset: 0))
                x += columnWidths[c] + gap
            }
            let rowBox = MathBox.hbox(HBox(
                children: rowPlacements, width: gridWidth,
                height: rowHeights[r], depth: rowDepths[r], scriptLevel: style.scriptLevel))
            gridChildren.append(Placement(box: rowBox, xOffset: 0, yOffset: rowBaselineY))
            y = rowBaselineY + rowDepths[r] + metrics.matrixRowGap
        }

        let gridTotalHeight = max(0, y - (cellBoxes.isEmpty ? 0 : metrics.matrixRowGap))
        let axis = metrics.axisHeight
        // Center the grid vertically on the axis.
        let gridHeight = gridTotalHeight / 2 + axis
        let gridDepth = gridTotalHeight / 2 - axis

        let grid = MathBox.vbox(VBox(
            children: gridChildren, width: gridWidth,
            height: gridHeight, depth: gridDepth, scriptLevel: style.scriptLevel))

        // Wrap in delimiters per environment.
        let (left, right) = matrixDelimiters(env)
        if left == "." && right == "." {
            return grid
        }
        return layoutDelimitedBox(left: left, right: right, body: grid, style: style, metrics: metrics)
    }

    /// Wraps an already-laid-out box in auto-sized delimiters.
    private static func layoutDelimitedBox(
        left: String, right: String, body bodyBox: MathBox,
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let axis = metrics.axisHeight
        let halfTarget = max(bodyBox.height - axis, bodyBox.depth + axis) + metrics.delimiterPadding
        let delimHeight = halfTarget + axis
        let delimDepth = halfTarget - axis

        var placements: [Placement] = []
        var x = 0.0
        if left != "." {
            let lb = stretchyDelimiter(left, height: delimHeight, depth: delimDepth, style: style, metrics: metrics)
            placements.append(Placement(box: lb, xOffset: x, yOffset: 0))
            x += lb.width
        }
        placements.append(Placement(box: bodyBox, xOffset: x, yOffset: 0))
        x += bodyBox.width
        if right != "." {
            let rb = stretchyDelimiter(right, height: delimHeight, depth: delimDepth, style: style, metrics: metrics)
            placements.append(Placement(box: rb, xOffset: x, yOffset: 0))
            x += rb.width
        }
        return .hbox(HBox(
            children: placements, width: x,
            height: max(bodyBox.height, delimHeight),
            depth: max(bodyBox.depth, delimDepth),
            scriptLevel: style.scriptLevel))
    }

    /// Returns the bracketing delimiters for a matrix environment.
    private static func matrixDelimiters(_ env: String) -> (String, String) {
        switch env {
        case "pmatrix": return ("(", ")")
        case "bmatrix": return ("[", "]")
        case "Bmatrix": return ("{", "}")
        case "vmatrix": return ("|", "|")
        case "Vmatrix": return ("\u{2016}", "\u{2016}")
        case "cases": return ("{", ".")
        default: return (".", ".")
        }
    }

    // MARK: - Accents

    /// Lays out an accent glyph above its base.
    private static func layoutAccent(
        kind: String, base: [MathNode],
        style: MathStyle, metrics: MathMetrics
    ) -> MathBox {
        let baseBox = layoutList(base, style: style)
        let accentGlyph = accentSymbol(kind)
        let gap = metrics.radicalGap

        if kind == "overline" || kind == "underline" {
            // A rule above or below the base.
            let rule = Rule(width: baseBox.width, height: metrics.defaultRuleThickness, depth: 0, scriptLevel: style.scriptLevel)
            if kind == "underline" {
                let baselineY = baseBox.height
                let ruleY = baselineY + baseBox.depth + gap + metrics.defaultRuleThickness
                return .vbox(VBox(
                    children: [
                        Placement(box: baseBox, xOffset: 0, yOffset: baselineY),
                        Placement(box: .rule(rule), xOffset: 0, yOffset: ruleY),
                    ],
                    width: baseBox.width, height: baselineY,
                    depth: baseBox.depth + gap + metrics.defaultRuleThickness,
                    scriptLevel: style.scriptLevel))
            } else {
                let ruleY = metrics.defaultRuleThickness
                let baselineY = ruleY + gap + baseBox.height
                return .vbox(VBox(
                    children: [
                        Placement(box: .rule(rule), xOffset: 0, yOffset: ruleY),
                        Placement(box: baseBox, xOffset: 0, yOffset: baselineY),
                    ],
                    width: baseBox.width, height: baselineY, depth: baseBox.depth,
                    scriptLevel: style.scriptLevel))
            }
        }

        let accBox = glyphBox(accentGlyph, style: style, metrics: metrics)
        let accentX = (baseBox.width - accBox.width) / 2
        let accentY = accBox.height                       // accent baseline near top
        let baseBaselineY = accentY + gap + baseBox.height

        return .vbox(VBox(
            children: [
                Placement(box: .glyph(accBox), xOffset: max(0, accentX), yOffset: accentY),
                Placement(box: baseBox, xOffset: 0, yOffset: baseBaselineY),
            ],
            width: baseBox.width, height: baseBaselineY, depth: baseBox.depth,
            scriptLevel: style.scriptLevel))
    }

    /// Maps an accent command name to its combining/spacing glyph.
    private static func accentSymbol(_ kind: String) -> String {
        switch kind {
        case "hat", "widehat": return "^"
        case "bar": return "\u{00AF}"
        case "vec": return "\u{2192}"
        case "tilde", "widetilde": return "~"
        case "dot": return "\u{02D9}"
        case "ddot": return "\u{00A8}"
        case "check": return "\u{02C7}"
        case "breve": return "\u{02D8}"
        case "acute": return "\u{00B4}"
        case "grave": return "`"
        case "mathring": return "\u{02DA}"
        default: return "^"
        }
    }
}
