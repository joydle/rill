/// A node in the parsed LaTeX math tree produced by ``MathParser``.
///
/// `MathNode` is a pure, `Sendable` value type with no layout or UI knowledge;
/// the box-layout stage (`MathLayout`) consumes it. Unmapped control sequences
/// degrade to ``unknown(_:)`` rather than failing, honoring Rill's
/// never-crash, never-blank contract.
public indirect enum MathNode: Sendable, Hashable {
    /// A single rendered glyph: a literal character or a resolved command
    /// symbol (e.g. `"\u{03B1}"` for `\alpha`).
    case symbol(String)

    /// A fraction with numerator and denominator sub-trees.
    case frac(numerator: [MathNode], denominator: [MathNode])

    /// A radical. `index` is the optional degree (the `n` in `\sqrt[n]{…}`);
    /// `radicand` is the expression under the root.
    case sqrt(index: [MathNode]?, radicand: [MathNode])

    /// A base carrying an optional superscript and/or subscript.
    case scripts(base: [MathNode], sup: [MathNode]?, sub: [MathNode]?)

    /// A big operator (sum/prod/int/…) with optional lower and upper limits.
    /// `op` is the resolved operator glyph.
    case bigOp(op: String, lower: [MathNode]?, upper: [MathNode]?)

    /// An auto-sized delimited group, `\left<left> … \right<right>`.
    case delimited(left: String, right: String, body: [MathNode])

    /// A matrix-family environment. `rows` is a 2-D array: each row is an array
    /// of cells, and each cell is an array of nodes.
    case matrix(env: String, rows: [[[MathNode]]])

    /// An accent (`hat`, `bar`, `vec`, `tilde`, `dot`, …) over a base.
    case accent(kind: String, base: [MathNode])

    /// Explicit LaTeX spacing (`\,`, `\;`, `\quad`, …).
    case space

    /// Literal text from `\text{…}`, rendered in an upright/roman style.
    case text(String)

    /// An explicit `{ … }` group, preserving its grouping semantics.
    case group([MathNode])

    /// An unmapped control sequence, stored without its backslash. Renderers
    /// display this as literal escaped text.
    case unknown(String)
}
