/// Classifies a LaTeX command so the layout engine can apply correct spacing
/// and positioning rules (TeX gives binary operators, relations, and big
/// operators different surrounding space).
public enum MathCommandCategory: Sendable, Hashable {
    /// Greek letters, upper and lower case.
    case greek
    /// Relation symbols (`=`-like): `\leq`, `\geq`, `\neq`, `\approx`, …
    case relation
    /// Binary operators: `\times`, `\cdot`, `\pm`, `\cup`, …
    case binaryOperator
    /// Arrows: `\to`, `\rightarrow`, `\mapsto`, `\Leftrightarrow`, …
    case arrow
    /// Big operators that take limits: `\sum`, `\prod`, `\int`, `\lim`, …
    case bigOperator
    /// Delimiters usable with `\left`/`\right`: `\langle`, `\lfloor`, …
    case delimiter
    /// Accents applied over a base: `\hat`, `\bar`, `\vec`, …
    case accent
    /// Named functions and miscellaneous standalone symbols: `\infty`,
    /// `\partial`, `\nabla`, `\sin`, `\log`, …
    case symbol
    /// Font/style switches: `\mathbb`, `\mathcal`, `\mathbf`, `\mathrm`.
    case font
    /// Explicit spacing commands: `\,`, `\;`, `\quad`, …
    case space
}

/// A resolved command: the glyph (or marker) to render and its category.
public struct MathCommand: Sendable, Hashable {
    /// The Unicode symbol the command renders to. For structural commands
    /// (fonts, accents, big operators) this is the operator/base glyph or the
    /// style name; structural handling lives in ``MathParser``.
    public let symbol: String
    /// The command's spacing/positioning class.
    public let category: MathCommandCategory

    /// Creates a resolved command entry.
    /// - Parameters:
    ///   - symbol: The Unicode glyph (or marker) the command maps to.
    ///   - category: The command's spacing/positioning class.
    public init(symbol: String, category: MathCommandCategory) {
        self.symbol = symbol
        self.category = category
    }
}

/// The static lookup table mapping 337 LaTeX control-sequence names to a
/// ``MathCommand``. Unmapped names return `nil`, which the parser surfaces as
/// ``MathNode/unknown(_:)`` for graceful degradation.
public enum MathCommandTable: Sendable {

    /// Resolves a command name (without the leading backslash).
    /// - Parameter name: The control-sequence name, e.g. `"alpha"`.
    /// - Returns: The mapped ``MathCommand`` or `nil` if unmapped.
    public static func lookup(_ name: String) -> MathCommand? {
        table[name]
    }

    /// The number of mapped commands (used to guard table coverage).
    public static var count: Int { table.count }

    private static func g(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .greek) }
    private static func r(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .relation) }
    private static func b(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .binaryOperator) }
    private static func a(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .arrow) }
    private static func big(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .bigOperator) }
    private static func d(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .delimiter) }
    private static func acc(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .accent) }
    private static func sym(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .symbol) }
    private static func font(_ s: String) -> MathCommand { MathCommand(symbol: s, category: .font) }
    private static func sp() -> MathCommand { MathCommand(symbol: " ", category: .space) }

    private static let table: [String: MathCommand] = {
        var t: [String: MathCommand] = [:]

        // MARK: Greek — lowercase
        t["alpha"] = g("\u{03B1}")
        t["beta"] = g("\u{03B2}")
        t["gamma"] = g("\u{03B3}")
        t["delta"] = g("\u{03B4}")
        t["epsilon"] = g("\u{03F5}")
        t["varepsilon"] = g("\u{03B5}")
        t["zeta"] = g("\u{03B6}")
        t["eta"] = g("\u{03B7}")
        t["theta"] = g("\u{03B8}")
        t["vartheta"] = g("\u{03D1}")
        t["iota"] = g("\u{03B9}")
        t["kappa"] = g("\u{03BA}")
        t["lambda"] = g("\u{03BB}")
        t["mu"] = g("\u{03BC}")
        t["nu"] = g("\u{03BD}")
        t["xi"] = g("\u{03BE}")
        t["omicron"] = g("\u{03BF}")
        t["pi"] = g("\u{03C0}")
        t["varpi"] = g("\u{03D6}")
        t["rho"] = g("\u{03C1}")
        t["varrho"] = g("\u{03F1}")
        t["sigma"] = g("\u{03C3}")
        t["varsigma"] = g("\u{03C2}")
        t["tau"] = g("\u{03C4}")
        t["upsilon"] = g("\u{03C5}")
        t["phi"] = g("\u{03D5}")
        t["varphi"] = g("\u{03C6}")
        t["chi"] = g("\u{03C7}")
        t["psi"] = g("\u{03C8}")
        t["omega"] = g("\u{03C9}")

        // MARK: Greek — uppercase
        t["Gamma"] = g("\u{0393}")
        t["Delta"] = g("\u{0394}")
        t["Theta"] = g("\u{0398}")
        t["Lambda"] = g("\u{039B}")
        t["Xi"] = g("\u{039E}")
        t["Pi"] = g("\u{03A0}")
        t["Sigma"] = g("\u{03A3}")
        t["Upsilon"] = g("\u{03A5}")
        t["Phi"] = g("\u{03A6}")
        t["Psi"] = g("\u{03A8}")
        t["Omega"] = g("\u{03A9}")

        // MARK: Relations
        t["leq"] = r("\u{2264}")
        t["le"] = r("\u{2264}")
        t["geq"] = r("\u{2265}")
        t["ge"] = r("\u{2265}")
        t["neq"] = r("\u{2260}")
        t["ne"] = r("\u{2260}")
        t["equiv"] = r("\u{2261}")
        t["approx"] = r("\u{2248}")
        t["cong"] = r("\u{2245}")
        t["simeq"] = r("\u{2243}")
        t["sim"] = r("\u{223C}")
        t["propto"] = r("\u{221D}")
        t["ll"] = r("\u{226A}")
        t["gg"] = r("\u{226B}")
        t["prec"] = r("\u{227A}")
        t["succ"] = r("\u{227B}")
        t["preceq"] = r("\u{2AAF}")
        t["succeq"] = r("\u{2AB0}")
        t["subset"] = r("\u{2282}")
        t["supset"] = r("\u{2283}")
        t["subseteq"] = r("\u{2286}")
        t["supseteq"] = r("\u{2287}")
        t["sqsubseteq"] = r("\u{2291}")
        t["sqsupseteq"] = r("\u{2292}")
        t["in"] = r("\u{2208}")
        t["ni"] = r("\u{220B}")
        t["notin"] = r("\u{2209}")
        t["mid"] = r("\u{2223}")
        t["parallel"] = r("\u{2225}")
        t["perp"] = r("\u{22A5}")
        t["models"] = r("\u{22A8}")
        t["vdash"] = r("\u{22A2}")
        t["dashv"] = r("\u{22A3}")
        t["doteq"] = r("\u{2250}")
        t["asymp"] = r("\u{224D}")
        t["bowtie"] = r("\u{22C8}")
        t["frown"] = r("\u{2322}")
        t["smile"] = r("\u{2323}")
        t["gtrsim"] = r("\u{2273}")
        t["lesssim"] = r("\u{2272}")

        // MARK: Binary operators
        t["times"] = b("\u{00D7}")
        t["div"] = b("\u{00F7}")
        t["cdot"] = b("\u{22C5}")
        t["pm"] = b("\u{00B1}")
        t["mp"] = b("\u{2213}")
        t["ast"] = b("\u{2217}")
        t["star"] = b("\u{22C6}")
        t["circ"] = b("\u{2218}")
        t["bullet"] = b("\u{2219}")
        t["oplus"] = b("\u{2295}")
        t["ominus"] = b("\u{2296}")
        t["otimes"] = b("\u{2297}")
        t["oslash"] = b("\u{2298}")
        t["odot"] = b("\u{2299}")
        t["cup"] = b("\u{222A}")
        t["cap"] = b("\u{2229}")
        t["uplus"] = b("\u{228E}")
        t["sqcup"] = b("\u{2294}")
        t["sqcap"] = b("\u{2293}")
        t["vee"] = b("\u{2228}")
        t["wedge"] = b("\u{2227}")
        t["setminus"] = b("\u{2216}")
        t["wr"] = b("\u{2240}")
        t["diamond"] = b("\u{22C4}")
        t["bigtriangleup"] = b("\u{25B3}")
        t["bigtriangledown"] = b("\u{25BD}")
        t["triangleleft"] = b("\u{25C1}")
        t["triangleright"] = b("\u{25B7}")
        t["dagger"] = b("\u{2020}")
        t["ddagger"] = b("\u{2021}")
        t["amalg"] = b("\u{2A3F}")
        t["lhd"] = b("\u{22B2}")
        t["rhd"] = b("\u{22B3}")

        // MARK: Arrows
        t["to"] = a("\u{2192}")
        t["rightarrow"] = a("\u{2192}")
        t["leftarrow"] = a("\u{2190}")
        t["gets"] = a("\u{2190}")
        t["leftrightarrow"] = a("\u{2194}")
        t["Rightarrow"] = a("\u{21D2}")
        t["Leftarrow"] = a("\u{21D0}")
        t["Leftrightarrow"] = a("\u{21D4}")
        t["mapsto"] = a("\u{21A6}")
        t["longmapsto"] = a("\u{27FC}")
        t["longrightarrow"] = a("\u{27F6}")
        t["longleftarrow"] = a("\u{27F5}")
        t["longleftrightarrow"] = a("\u{27F7}")
        t["Longrightarrow"] = a("\u{27F9}")
        t["Longleftarrow"] = a("\u{27F8}")
        t["Longleftrightarrow"] = a("\u{27FA}")
        t["uparrow"] = a("\u{2191}")
        t["downarrow"] = a("\u{2193}")
        t["updownarrow"] = a("\u{2195}")
        t["Uparrow"] = a("\u{21D1}")
        t["Downarrow"] = a("\u{21D3}")
        t["nearrow"] = a("\u{2197}")
        t["searrow"] = a("\u{2198}")
        t["swarrow"] = a("\u{2199}")
        t["nwarrow"] = a("\u{2196}")
        t["hookleftarrow"] = a("\u{21A9}")
        t["hookrightarrow"] = a("\u{21AA}")
        t["leftharpoonup"] = a("\u{21BC}")
        t["rightharpoonup"] = a("\u{21C0}")
        t["leftharpoondown"] = a("\u{21BD}")
        t["rightharpoondown"] = a("\u{21C1}")
        t["rightleftharpoons"] = a("\u{21CC}")
        t["leadsto"] = a("\u{21DD}")
        t["implies"] = a("\u{27F9}")
        t["iff"] = a("\u{27FA}")

        // MARK: Big operators
        t["sum"] = big("\u{2211}")
        t["prod"] = big("\u{220F}")
        t["coprod"] = big("\u{2210}")
        t["int"] = big("\u{222B}")
        t["iint"] = big("\u{222C}")
        t["iiint"] = big("\u{222D}")
        t["oint"] = big("\u{222E}")
        t["bigcup"] = big("\u{22C3}")
        t["bigcap"] = big("\u{22C2}")
        t["bigsqcup"] = big("\u{2A06}")
        t["bigvee"] = big("\u{22C1}")
        t["bigwedge"] = big("\u{22C0}")
        t["bigoplus"] = big("\u{2A01}")
        t["bigotimes"] = big("\u{2A02}")
        t["bigodot"] = big("\u{2A00}")
        t["biguplus"] = big("\u{2A04}")
        t["lim"] = big("lim")
        t["limsup"] = big("lim sup")
        t["liminf"] = big("lim inf")
        t["max"] = big("max")
        t["min"] = big("min")
        t["sup"] = big("sup")
        t["inf"] = big("inf")
        t["gcd"] = big("gcd")

        // MARK: Delimiters
        t["langle"] = d("\u{27E8}")
        t["rangle"] = d("\u{27E9}")
        t["lfloor"] = d("\u{230A}")
        t["rfloor"] = d("\u{230B}")
        t["lceil"] = d("\u{2308}")
        t["rceil"] = d("\u{2309}")
        t["lbrace"] = d("{")
        t["rbrace"] = d("}")
        t["lbrack"] = d("[")
        t["rbrack"] = d("]")
        t["vert"] = d("|")
        t["Vert"] = d("\u{2016}")
        t["backslash"] = d("\\")
        t["lvert"] = d("|")
        t["rvert"] = d("|")
        t["lVert"] = d("\u{2016}")
        t["rVert"] = d("\u{2016}")
        t["ulcorner"] = d("\u{231C}")
        t["urcorner"] = d("\u{231D}")
        t["llcorner"] = d("\u{231E}")
        t["lrcorner"] = d("\u{231F}")

        // MARK: Accents (structural — applied over a base)
        t["hat"] = acc("hat")
        t["widehat"] = acc("widehat")
        t["bar"] = acc("bar")
        t["overline"] = acc("overline")
        t["vec"] = acc("vec")
        t["tilde"] = acc("tilde")
        t["widetilde"] = acc("widetilde")
        t["dot"] = acc("dot")
        t["ddot"] = acc("ddot")
        t["dddot"] = acc("dddot")
        t["check"] = acc("check")
        t["breve"] = acc("breve")
        t["acute"] = acc("acute")
        t["grave"] = acc("grave")
        t["mathring"] = acc("mathring")
        t["underline"] = acc("underline")

        // MARK: Fonts / styles (structural)
        t["mathbb"] = font("mathbb")
        t["mathcal"] = font("mathcal")
        t["mathbf"] = font("mathbf")
        t["mathrm"] = font("mathrm")
        t["mathit"] = font("mathit")
        t["mathsf"] = font("mathsf")
        t["mathtt"] = font("mathtt")
        t["mathfrak"] = font("mathfrak")
        t["boldsymbol"] = font("boldsymbol")
        t["bm"] = font("bm")
        t["text"] = font("text")
        t["textrm"] = font("textrm")
        t["textbf"] = font("textbf")
        t["textit"] = font("textit")
        t["operatorname"] = font("operatorname")

        // MARK: Spacing
        t[","] = sp()
        t[":"] = sp()
        t[";"] = sp()
        t["!"] = sp()
        t[" "] = sp()
        t["quad"] = sp()
        t["qquad"] = sp()
        t["thinspace"] = sp()
        t["medspace"] = sp()
        t["thickspace"] = sp()
        t["enspace"] = sp()
        t["nobreakspace"] = sp()

        // MARK: Named functions
        t["sin"] = sym("sin")
        t["cos"] = sym("cos")
        t["tan"] = sym("tan")
        t["cot"] = sym("cot")
        t["sec"] = sym("sec")
        t["csc"] = sym("csc")
        t["arcsin"] = sym("arcsin")
        t["arccos"] = sym("arccos")
        t["arctan"] = sym("arctan")
        t["sinh"] = sym("sinh")
        t["cosh"] = sym("cosh")
        t["tanh"] = sym("tanh")
        t["coth"] = sym("coth")
        t["exp"] = sym("exp")
        t["ln"] = sym("ln")
        t["log"] = sym("log")
        t["lg"] = sym("lg")
        t["arg"] = sym("arg")
        t["deg"] = sym("deg")
        t["dim"] = sym("dim")
        t["hom"] = sym("hom")
        t["ker"] = sym("ker")
        t["det"] = sym("det")
        t["Pr"] = sym("Pr")

        // MARK: Miscellaneous symbols
        t["infty"] = sym("\u{221E}")
        t["partial"] = sym("\u{2202}")
        t["nabla"] = sym("\u{2207}")
        t["forall"] = sym("\u{2200}")
        t["exists"] = sym("\u{2203}")
        t["nexists"] = sym("\u{2204}")
        t["emptyset"] = sym("\u{2205}")
        t["varnothing"] = sym("\u{2205}")
        t["neg"] = sym("\u{00AC}")
        t["lnot"] = sym("\u{00AC}")
        t["top"] = sym("\u{22A4}")
        t["bot"] = sym("\u{22A5}")
        t["angle"] = sym("\u{2220}")
        t["measuredangle"] = sym("\u{2221}")
        t["triangle"] = sym("\u{25B3}")
        t["square"] = sym("\u{25A1}")
        t["blacksquare"] = sym("\u{25A0}")
        t["diamondsuit"] = sym("\u{2662}")
        t["heartsuit"] = sym("\u{2661}")
        t["clubsuit"] = sym("\u{2663}")
        t["spadesuit"] = sym("\u{2660}")
        t["flat"] = sym("\u{266D}")
        t["natural"] = sym("\u{266E}")
        t["sharp"] = sym("\u{266F}")
        t["aleph"] = sym("\u{2135}")
        t["beth"] = sym("\u{2136}")
        t["gimel"] = sym("\u{2137}")
        t["hbar"] = sym("\u{210F}")
        t["hslash"] = sym("\u{210F}")
        t["ell"] = sym("\u{2113}")
        t["wp"] = sym("\u{2118}")
        t["Re"] = sym("\u{211C}")
        t["Im"] = sym("\u{2111}")
        t["mho"] = sym("\u{2127}")
        t["prime"] = sym("\u{2032}")
        t["backprime"] = sym("\u{2035}")
        t["surd"] = sym("\u{221A}")
        t["circledR"] = sym("\u{00AE}")
        t["circledS"] = sym("\u{24C8}")
        t["complement"] = sym("\u{2201}")
        t["Bbbk"] = sym("\u{1D55C}")
        t["cdots"] = sym("\u{22EF}")
        t["ldots"] = sym("\u{2026}")
        t["dots"] = sym("\u{2026}")
        t["vdots"] = sym("\u{22EE}")
        t["ddots"] = sym("\u{22F1}")
        t["because"] = sym("\u{2235}")
        t["therefore"] = sym("\u{2234}")
        t["pounds"] = sym("\u{00A3}")
        t["euro"] = sym("\u{20AC}")
        t["degree"] = sym("\u{00B0}")
        t["checkmark"] = sym("\u{2713}")
        t["maltese"] = sym("\u{2720}")
        t["S"] = sym("\u{00A7}")
        t["P"] = sym("\u{00B6}")
        t["copyright"] = sym("\u{00A9}")
        t["imath"] = sym("\u{0131}")
        t["jmath"] = sym("\u{0237}")
        t["bigstar"] = sym("\u{2605}")
        t["lozenge"] = sym("\u{25CA}")
        t["blacklozenge"] = sym("\u{29EB}")
        t["bigcirc"] = sym("\u{25EF}")
        t["sphericalangle"] = sym("\u{2222}")
        t["nmid"] = sym("\u{2224}")
        t["nparallel"] = sym("\u{2226}")
        t["smallsetminus"] = sym("\u{2216}")
        t["lll"] = sym("\u{22D8}")
        t["ggg"] = sym("\u{22D9}")
        t["between"] = sym("\u{226C}")
        t["pitchfork"] = sym("\u{22D4}")
        t["backsim"] = sym("\u{223D}")
        t["eqcirc"] = sym("\u{2256}")
        t["circeq"] = sym("\u{2257}")
        t["triangleq"] = sym("\u{225C}")
        t["risingdotseq"] = sym("\u{2253}")
        t["fallingdotseq"] = sym("\u{2252}")

        return t
    }()
}
