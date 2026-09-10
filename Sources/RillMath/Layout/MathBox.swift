/// A node in the TeX-style box tree produced by ``MathLayout``.
///
/// Every box carries `(width, height, depth)` metrics measured from its
/// baseline (`height` above, `depth` below) plus the `scriptLevel` it was laid
/// out at. The renderer (RillUI) walks this tree to draw glyphs and rules; the
/// tree itself is pure and `Sendable`, so layout is fully unit-testable on
/// metrics with no UI involved.
///
/// Coordinate conventions:
/// - An `hbox` lays children left-to-right on a shared baseline; each child
///   records its `xOffset` from the hbox's left edge.
/// - A `vbox` stacks children top-to-bottom; each child records its `yOffset`
///   (distance from the vbox's top down to the child's own baseline) and an
///   `xOffset` for horizontal alignment. The vbox's `height` is the distance
///   from its top to its reference baseline, and `depth` the remainder.
public indirect enum MathBox: Sendable, Hashable {
    /// A single drawn glyph (a symbol or text character).
    case glyph(Glyph)
    /// A solid filled rectangle (fraction bar, radical rule, matrix line).
    case rule(Rule)
    /// Stretchable/empty horizontal or vertical space.
    case glue(Glue)
    /// A horizontal list of child placements sharing a baseline.
    case hbox(HBox)
    /// A vertical stack of child placements.
    case vbox(VBox)

    /// The advance width of the box in points.
    public var width: Double {
        switch self {
        case .glyph(let g): return g.width
        case .rule(let r): return r.width
        case .glue(let g): return g.width
        case .hbox(let h): return h.width
        case .vbox(let v): return v.width
        }
    }

    /// The extent above the baseline in points.
    public var height: Double {
        switch self {
        case .glyph(let g): return g.height
        case .rule(let r): return r.height
        case .glue(let g): return g.height
        case .hbox(let h): return h.height
        case .vbox(let v): return v.height
        }
    }

    /// The extent below the baseline in points.
    public var depth: Double {
        switch self {
        case .glyph(let g): return g.depth
        case .rule(let r): return r.depth
        case .glue(let g): return g.depth
        case .hbox(let h): return h.depth
        case .vbox(let v): return v.depth
        }
    }

    /// The TeX script level the box was laid out at (0 = base, 2 = floor).
    public var scriptLevel: Int {
        switch self {
        case .glyph(let g): return g.scriptLevel
        case .rule(let r): return r.scriptLevel
        case .glue(let g): return g.scriptLevel
        case .hbox(let h): return h.scriptLevel
        case .vbox(let v): return v.scriptLevel
        }
    }
}

/// A single drawn glyph with its measured metrics.
public struct Glyph: Sendable, Hashable {
    /// The Unicode string to draw (usually one extended grapheme).
    public let glyph: String
    /// Advance width in points.
    public let width: Double
    /// Height above the baseline in points.
    public let height: Double
    /// Depth below the baseline in points.
    public let depth: Double
    /// The script level this glyph was sized at.
    public let scriptLevel: Int

    /// Creates a glyph box.
    public init(glyph: String, width: Double, height: Double, depth: Double, scriptLevel: Int) {
        self.glyph = glyph
        self.width = width
        self.height = height
        self.depth = depth
        self.scriptLevel = scriptLevel
    }
}

/// A solid filled rectangle used for fraction bars, radical rules, and matrix
/// separators.
public struct Rule: Sendable, Hashable {
    /// Width in points.
    public let width: Double
    /// Height above the baseline in points.
    public let height: Double
    /// Depth below the baseline in points.
    public let depth: Double
    /// The script level the rule was sized at.
    public let scriptLevel: Int

    /// Creates a rule box. `height + depth` is the rule's drawn thickness.
    public init(width: Double, height: Double, depth: Double, scriptLevel: Int) {
        self.width = width
        self.height = height
        self.depth = depth
        self.scriptLevel = scriptLevel
    }
}

/// Empty/stretchable space contributing to a box's extent.
public struct Glue: Sendable, Hashable {
    /// Width in points.
    public let width: Double
    /// Height above the baseline in points.
    public let height: Double
    /// Depth below the baseline in points.
    public let depth: Double
    /// The script level the glue was created at.
    public let scriptLevel: Int

    /// Creates a glue box. Use zero height/depth for horizontal spacing and zero
    /// width for vertical spacing.
    public init(width: Double, height: Double = 0, depth: Double = 0, scriptLevel: Int) {
        self.width = width
        self.height = height
        self.depth = depth
        self.scriptLevel = scriptLevel
    }
}

/// A horizontal list: children laid out left-to-right on a shared baseline.
public struct HBox: Sendable, Hashable {
    /// The placed children, each with its horizontal offset from the left edge.
    public let children: [Placement]
    /// Total advance width in points.
    public let width: Double
    /// Maximum child height above the baseline.
    public let height: Double
    /// Maximum child depth below the baseline.
    public let depth: Double
    /// The script level the hbox was laid out at.
    public let scriptLevel: Int

    /// Creates an hbox from already-placed children and computed metrics.
    public init(children: [Placement], width: Double, height: Double, depth: Double, scriptLevel: Int) {
        self.children = children
        self.width = width
        self.height = height
        self.depth = depth
        self.scriptLevel = scriptLevel
    }
}

/// A vertical stack: children placed top-to-bottom relative to the box's top.
public struct VBox: Sendable, Hashable {
    /// The placed children, each with `yOffset` (top→child baseline) and
    /// `xOffset` (left→child left edge).
    public let children: [Placement]
    /// Total advance width in points.
    public let width: Double
    /// Extent above the vbox's reference baseline.
    public let height: Double
    /// Extent below the vbox's reference baseline.
    public let depth: Double
    /// The script level the vbox was laid out at.
    public let scriptLevel: Int

    /// Creates a vbox from already-placed children and computed metrics.
    public init(children: [Placement], width: Double, height: Double, depth: Double, scriptLevel: Int) {
        self.children = children
        self.width = width
        self.height = height
        self.depth = depth
        self.scriptLevel = scriptLevel
    }
}

/// A child box positioned within an ``HBox`` or ``VBox``.
///
/// - In an `HBox`, `xOffset` is the distance from the parent's left edge to the
///   child's left edge; `yOffset` is 0 (shared baseline).
/// - In a `VBox`, `yOffset` is the distance from the parent's top down to the
///   child's own baseline; `xOffset` aligns the child horizontally.
public struct Placement: Sendable, Hashable {
    /// The placed box.
    public let box: MathBox
    /// Horizontal offset from the parent's left edge to the child's left edge.
    public let xOffset: Double
    /// Vertical offset. In a vbox, distance from the parent top to the child's
    /// baseline; in an hbox, baseline shift (0 unless raised/lowered).
    public let yOffset: Double

    /// Creates a placement.
    public init(box: MathBox, xOffset: Double, yOffset: Double) {
        self.box = box
        self.xOffset = xOffset
        self.yOffset = yOffset
    }
}
