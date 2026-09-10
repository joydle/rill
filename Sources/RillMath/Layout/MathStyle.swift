/// A TeX math style governing font size and script level during layout.
///
/// TeX defines four base styles. Rill collapses cramped variants but preserves
/// the essential distinction that drives positioning: `display` stacks limits
/// above/below big operators while `text` places them beside, and each
/// successive `scriptLevel` shrinks the font for super/subscripts.
public enum MathStyle: Sendable, Hashable {
    /// Display style: stand-alone equations. Big-operator limits stack
    /// above/below; fractions use full size.
    case display
    /// Text (inline) style: math inside a line of prose. Big-operator limits sit
    /// beside the operator.
    case text
    /// Script style: first-level super/subscripts.
    case script
    /// Script-script style: nested super/subscripts (the size floor).
    case scriptScript

    /// The nesting depth used to shrink fonts. `display`/`text` are level 0;
    /// `script` is 1; `scriptScript` is 2.
    public var scriptLevel: Int {
        switch self {
        case .display, .text: return 0
        case .script: return 1
        case .scriptScript: return 2
        }
    }

    /// Whether this style stacks big-operator limits above/below (`display`)
    /// rather than placing them beside the operator.
    public var stacksLimits: Bool { self == .display }

    /// The base font size (in points) for the unit em used by ``MathMetrics``.
    public static let baseFontSize: Double = 16.0

    /// The font size in points for content laid out in this style. Each script
    /// level multiplies by a shrink factor (0.7, then 0.5 of base — matching
    /// TeX's `scriptPercentScaleDown`/`scriptScriptPercentScaleDown`).
    public var fontSize: Double {
        switch self {
        case .display, .text: return MathStyle.baseFontSize
        case .script: return MathStyle.baseFontSize * 0.7
        case .scriptScript: return MathStyle.baseFontSize * 0.5
        }
    }

    /// The style used for content placed in a superscript or subscript of a base
    /// laid out in this style. `display`/`text` → `script`; `script` and
    /// `scriptScript` → `scriptScript` (the floor).
    public var superStyle: MathStyle {
        switch self {
        case .display, .text: return .script
        case .script, .scriptScript: return .scriptScript
        }
    }

    /// The style used for sub/superscripts; identical to ``superStyle`` (TeX uses
    /// the same shrink for both).
    public var subStyle: MathStyle { superStyle }

    /// The style used for a fraction's numerator/denominator. In `display` the
    /// parts drop to `text`; otherwise they shrink one script level.
    public var fractionStyle: MathStyle {
        switch self {
        case .display: return .text
        case .text: return .script
        case .script, .scriptScript: return .scriptScript
        }
    }

    /// The style used for content under a radical or inside a delimited group:
    /// the same size as the surrounding style.
    public var sameSize: MathStyle { self }
}
