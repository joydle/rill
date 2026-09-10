import SwiftUI
import RillMath

/// Draws a laid-out ``MathBox`` tree into a SwiftUI `Canvas` using CoreText
/// glyphs and filled rules — no images, no bundled font atlas, no `iosMath`.
///
/// `MathBoxRenderer` is a pure flattening pass: it walks the recursive box tree
/// produced by ``MathLayout`` and emits a flat list of ``Command`` values, each
/// positioned in absolute Canvas coordinates (origin at the top-left of the
/// drawing area, y growing downward). The flattening is unit-testable on the
/// command list alone, with no pixels involved; the SwiftUI `Canvas` body then
/// paints each command.
///
/// Coordinate translation: ``MathBox`` measures children from a baseline
/// (`height` above, `depth` below). The renderer is handed the absolute y of the
/// box's reference baseline and converts every child placement — whose `yOffset`
/// is a baseline shift in an hbox and a top-down distance in a vbox — into an
/// absolute baseline y for that child, recursing until it reaches `glyph` and
/// `rule` leaves.
public enum MathBoxRenderer {

    /// A single absolute-positioned drawing instruction emitted while flattening
    /// a ``MathBox`` tree.
    public enum Command: Sendable, Equatable {
        /// Draw `text` so that its baseline sits at `baseline` with its left edge
        /// at `x`, sized for `scriptLevel`.
        case glyph(text: String, x: Double, baseline: Double, scriptLevel: Int)
        /// Fill a solid rectangle (fraction bar, radical rule, matrix line).
        case rule(x: Double, y: Double, width: Double, height: Double)
    }

    /// Flattens a laid-out box into absolute-positioned draw commands.
    ///
    /// The box is positioned with its left edge at `origin.x` and its reference
    /// baseline at `origin.y + box.height`, so the whole box fits in a frame of
    /// `size(of:)`. `color` is accepted for API symmetry with the Canvas drawing
    /// path; the returned commands are color-agnostic (the Canvas applies the
    /// theme color uniformly).
    ///
    /// - Parameters:
    ///   - box: The laid-out ``MathBox``.
    ///   - origin: The top-left point the box is drawn from.
    ///   - color: The glyph/rule color (used by the Canvas, not stored here).
    /// - Returns: A flat, paint-order list of ``Command`` values.
    public static func drawCommands(
        for box: MathBox,
        origin: CGPoint = .zero,
        color: Color
    ) -> [Command] {
        var commands: [Command] = []
        flatten(box, x: origin.x, baseline: origin.y + box.height, into: &commands)
        return commands
    }

    /// The frame size required to draw `box` with no clipping.
    public static func size(of box: MathBox) -> CGSize {
        CGSize(width: box.width, height: box.height + box.depth)
    }

    // MARK: - Flattening

    /// Recursively appends draw commands for `box`, given the absolute position
    /// of its left edge (`x`) and its reference baseline (`baseline`).
    private static func flatten(
        _ box: MathBox,
        x: Double,
        baseline: Double,
        into commands: inout [Command]
    ) {
        switch box {
        case .glyph(let g):
            commands.append(.glyph(
                text: g.glyph,
                x: x,
                baseline: baseline,
                scriptLevel: g.scriptLevel
            ))

        case .rule(let r):
            // A rule's drawn thickness is `height + depth`; its top sits `height`
            // above the baseline.
            let thickness = r.height + r.depth
            commands.append(.rule(
                x: x,
                y: baseline - r.height,
                width: r.width,
                height: max(thickness, 0.5)
            ))

        case .glue:
            // Empty space contributes nothing to draw.
            break

        case .hbox(let h):
            // Children share the hbox baseline; `xOffset` shifts horizontally and
            // `yOffset` raises/lowers the child baseline (negative = up).
            for child in h.children {
                flatten(
                    child.box,
                    x: x + child.xOffset,
                    baseline: baseline + child.yOffset,
                    into: &commands
                )
            }

        case .vbox(let v):
            // Children are placed top-to-bottom; `yOffset` is the distance from
            // the vbox's TOP down to the child's own baseline. The vbox's top is
            // `height` above its reference baseline.
            let top = baseline - v.height
            for child in v.children {
                flatten(
                    child.box,
                    x: x + child.xOffset,
                    baseline: top + child.yOffset,
                    into: &commands
                )
            }
        }
    }
}
