/// Font-derived metrics that drive TeX-style positioning.
///
/// Real TeX reads these from a font's math table. Rill has no bundled font
/// atlas, so it derives a consistent, em-scaled set from the current font size.
/// All values are in points and scale linearly with ``fontSize`` so that script
/// levels stay proportional.
public struct MathMetrics: Sendable, Hashable {
    /// The font size (em) these metrics are scaled to.
    public let fontSize: Double

    /// Creates metrics scaled to `fontSize` points.
    /// - Parameter fontSize: The em size in points.
    public init(fontSize: Double) {
        self.fontSize = fontSize
    }

    /// The em unit (== ``fontSize``).
    public var em: Double { fontSize }

    /// Height of the math axis above the baseline. Fraction bars and big
    /// operators center on this line. TeX's `axisHeight` ≈ 0.25 em.
    public var axisHeight: Double { 0.25 * em }

    /// Default thickness of fraction bars and radical rules
    /// (TeX `defaultRuleThickness` ≈ 0.04 em).
    public var defaultRuleThickness: Double { 0.04 * em }

    /// Minimum gap between the numerator's depth and the fraction bar.
    public var numeratorGap: Double { 0.12 * em }

    /// Minimum gap between the fraction bar and the denominator's height.
    public var denominatorGap: Double { 0.12 * em }

    /// Standard shift of a superscript above the baseline.
    public var superscriptShift: Double { 0.45 * em }

    /// Standard drop of a subscript below the baseline.
    public var subscriptShift: Double { 0.2 * em }

    /// Horizontal gap between a base and its attached scripts.
    public var scriptSpace: Double { 0.05 * em }

    /// Vertical gap between a big operator and a stacked limit (display style).
    public var limitGap: Double { 0.15 * em }

    /// Vertical clearance between the radical overbar and the radicand.
    public var radicalGap: Double { 0.1 * em }

    /// Extra height the radical rule + ascender adds above the radicand.
    public var radicalExtraAscender: Double { 0.1 * em }

    /// The nominal x-height (height of a lowercase glyph without ascenders).
    public var xHeight: Double { 0.45 * em }

    /// The nominal cap height / ascent of a typical glyph.
    public var ascent: Double { 0.7 * em }

    /// The ascent reserved for tall glyphs whose ink reaches well above the
    /// nominal cap height — delimiters `( ) [ ] { } |`, big operators, integral,
    /// summation. Reserving this prevents the Canvas from clipping their tops.
    public var tallAscent: Double { 0.9 * em }

    /// The nominal descent of a typical glyph below the baseline.
    public var descent: Double { 0.2 * em }

    /// The nominal advance width of a single glyph.
    public var glyphWidth: Double { 0.5 * em }

    /// Horizontal padding placed inside an auto-sized delimiter.
    public var delimiterPadding: Double { 0.05 * em }

    /// Inter-column gap in a matrix grid.
    public var matrixColumnGap: Double { 0.6 * em }

    /// Inter-row gap in a matrix grid.
    public var matrixRowGap: Double { 0.3 * em }

    /// Width of a `\quad` / standard inter-atom space unit.
    public var quad: Double { em }

    /// Thin space (`\,`).
    public var thinSpace: Double { 0.167 * em }
}
