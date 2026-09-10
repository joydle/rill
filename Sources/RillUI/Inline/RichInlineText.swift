import SwiftUI
import RillCore
import RillAnalytics

/// Lays out a run of inline content as real, interactive SwiftUI.
///
/// `RichInlineText` is the inline layout path the block renderers
/// (``ParagraphView``, ``HeadingView``) use so the host hooks in
/// ``RenderConfig`` actually fire during rendering:
///
/// - **Links.** Activating a link routes through
///   ``InlineRenderer/handleLinkTap(url:context:)`` (via an injected
///   ``SwiftUI/OpenURLAction``), firing ``MarkdownInteraction/linkTapped(url:)``
///   and the host's ``RenderConfig/linkHandler`` — not SwiftUI's default
///   `openURL`.
/// - **Citations.** Each citation renders as an interactive ``CitationPill`` so a
///   tap reaches ``RenderConfig/citationResolver`` and
///   ``MarkdownInteraction/citationTapped(marker:index:)``.
/// - **Inline math.** Renders a ``MathView`` instead of raw LaTeX text.
/// - **Inline images.** Loads through ``RenderConfig/imageLoader`` with alt-text
///   fallback.
///
/// When the run is pure text (the overwhelmingly common case) it collapses to a
/// single, naturally-wrapping ``SwiftUI/Text`` for performance; only when an
/// image, inline math, or citation is present does it fall back to a wrapping
/// flow layout that interleaves text spans with the dedicated inline views.
struct RichInlineText: View {
    /// The inline run to lay out.
    let inlines: [Inline]

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// The base font applied to plain text spans (body for paragraphs, the
    /// per-level heading font for headings).
    let font: Font

    /// The foreground color applied to plain text spans.
    let color: Color

    /// Whether this run belongs to the active streaming tail block and may
    /// animate its newly appended text. Committed blocks pass `false`.
    let isActiveTail: Bool

    /// Creates a rich inline text view.
    /// - Parameters:
    ///   - inlines: The inline run to render.
    ///   - context: The render context supplying theme, config, and analytics.
    ///   - font: The base font for plain text. Defaults to the theme body font.
    ///   - color: The text color. Defaults to the theme primary text color.
    ///   - isActiveTail: Whether this is the live tail block (enables the append
    ///     reveal). Defaults to `false`.
    init(
        inlines: [Inline],
        context: BlockRenderContext,
        font: Font? = nil,
        color: Color? = nil,
        isActiveTail: Bool = false
    ) {
        self.inlines = inlines
        self.context = context
        self.font = font ?? context.theme.fonts.body
        self.color = color ?? context.theme.colors.textPrimary
        self.isActiveTail = isActiveTail
    }

    var body: some View {
        let segments = InlineRenderer.segments(
            inlines, theme: context.theme, config: context.config
        )
        content(for: segments)
            .environment(\.openURL, OpenURLAction { url in
                InlineRenderer.handleLinkTap(url: url.absoluteString, context: context)
                return .handled
            })
    }

    @ViewBuilder
    private func content(for segments: [InlineSegment]) -> some View {
        if segments.allSatisfy(Self.isText) {
            let combined = Self.combinedText(segments)
            if isActiveTail, context.config.appendAnimation != .none {
                // Live tail: reveal newly appended words via a SwiftUI animation
                // transaction tied to the document update (no per-char timer).
                StreamingText(
                    text: combined,
                    font: font,
                    color: color,
                    style: context.config.appendAnimation,
                    duration: context.config.appendAnimationDuration
                )
            } else {
                // Committed block (or animation disabled): static, naturally
                // wrapping Text — never animates.
                Text(combined)
                    .font(font)
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // Mixed run (text + pills/math/images). Break the text spans into
            // word chunks so the flow layout can wrap between words like real
            // text — otherwise a long text span is one atomic child that
            // overflows the line and clips. Non-text segments stay whole views.
            let items = Self.flowItems(for: segments)
            FlowLayout(hSpacing: 0, vSpacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    flowItemView(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One placeable unit in the wrapping flow: either a single word of text
    /// (carrying its run attributes and trailing whitespace) or a whole inline
    /// view (pill, math, image).
    private enum FlowItem {
        case word(AttributedString)
        case inline(InlineSegment)
    }

    @ViewBuilder
    private func flowItemView(_ item: FlowItem) -> some View {
        switch item {
        case .word(let attributed):
            Text(attributed)
                .font(font)
                .foregroundStyle(color)
        case .inline(let segment):
            segmentView(segment)
        }
    }

    /// Flattens segments into flow items, splitting every text span into words
    /// so the flow can wrap between them.
    private static func flowItems(for segments: [InlineSegment]) -> [FlowItem] {
        var items: [FlowItem] = []
        for segment in segments {
            if case .text(let attributed) = segment {
                items.append(contentsOf: splitWords(attributed).map(FlowItem.word))
            } else {
                items.append(.inline(segment))
            }
        }
        return items
    }

    /// Splits an attributed string into word chunks, each keeping its run
    /// attributes and any trailing whitespace so inter-word spacing survives.
    static func splitWords(_ attributed: AttributedString) -> [AttributedString] {
        var words: [AttributedString] = []
        var current = AttributedString()
        for run in attributed.runs {
            for character in attributed[run.range].characters {
                current.append(AttributedString(String(character), attributes: run.attributes))
                if character == " " || character == "\n" || character == "\t" {
                    words.append(current)
                    current = AttributedString()
                }
            }
        }
        if !current.characters.isEmpty {
            words.append(current)
        }
        return words
    }

    @ViewBuilder
    private func segmentView(_ segment: InlineSegment) -> some View {
        switch segment {
        case .text(let attributed):
            Text(attributed)
                .font(font)
                .foregroundStyle(color)
        case .citation(let citation):
            // A footnote reference (`[^id]`, parsed with a nil index) whose marker
            // resolves in the document's footnote registry renders as a tappable
            // superscript number; every other citation renders as a pill.
            if citation.index == nil, let number = context.footnotes.number(for: citation.marker) {
                FootnoteReferenceView(citation: citation, number: number, context: context)
            } else {
                CitationPill(citation: citation, context: context)
                    .padding(.horizontal, Self.inlineGap)
            }
        case .math(let latex):
            // A thin optical gap so the math glyphs never butt directly against an
            // adjacent digit/letter, independent of any source whitespace.
            MathView(latex: latex, style: .text, theme: context.theme)
                .padding(.horizontal, Self.inlineGap)
        case .image(let image):
            InlineImageView(image: image, context: context)
                .padding(.horizontal, Self.inlineGap)
        }
    }

    /// The thin horizontal padding placed around non-text inline atoms (math,
    /// images, citation pills) so they never collide with neighbouring glyphs.
    private static let inlineGap: CGFloat = 1.5

    /// Whether a segment is plain attributed text.
    private static func isText(_ segment: InlineSegment) -> Bool {
        if case .text = segment { return true }
        return false
    }

    /// Concatenates the attributed text of an all-text segment list.
    private static func combinedText(_ segments: [InlineSegment]) -> AttributedString {
        var result = AttributedString()
        for case .text(let attributed) in segments {
            result.append(attributed)
        }
        return result
    }
}

/// Loads and displays an inline image through ``RenderConfig/imageLoader``,
/// falling back to the alt text (or URL) until the image is available or if no
/// loader is installed.
struct InlineImageView: View {
    /// The image to load.
    let image: InlineImage

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// The loaded image, once the host's loader resolves it.
    @State private var loaded: SwiftUI.Image?

    /// Whether loading failed (so the fallback text stays shown).
    @State private var failed = false

    /// The inline image's box height, tracking the surrounding line height so it
    /// scales with Dynamic Type. A `.resizable()` image has no intrinsic size, so
    /// without a frame an `.unspecified` proposal collapses it to SwiftUI's tiny
    /// placeholder; constraining the height yields a stable, correct inline box.
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 20

    var body: some View {
        Group {
            if let loaded {
                loaded
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: lineHeight)
            } else {
                Text(image.alt.isEmpty ? image.url : image.alt)
                    .font(context.theme.fonts.body)
                    .foregroundStyle(context.theme.colors.textSecondary)
            }
        }
        .task { await load() }
    }

    /// Invokes the host image loader once, capturing the result or failure.
    private func load() async {
        guard loaded == nil, !failed,
              let loader = context.config.imageLoader,
              let url = URL(string: image.url)
        else { return }
        do {
            loaded = try await loader.image(for: url)
        } catch {
            failed = true
        }
    }
}

/// A minimal, **baseline-aware** line-wrapping layout: places subviews
/// left-to-right, wrapping to a new row when the next subview would overflow the
/// proposed width, and aligns every subview on a row to a shared text baseline.
/// Used to interleave text spans with inline pills, math, and images so that
/// taller children (inline math, citation pills, images) rest on the same
/// baseline as the surrounding words instead of being pinned to the row top.
struct FlowLayout: Layout {
    /// Horizontal spacing between adjacent subviews on a row.
    var hSpacing: CGFloat = 4
    /// Vertical spacing between wrapped rows.
    var vSpacing: CGFloat = 4

    /// A measured subview: its `.unspecified` size and the distance from its top
    /// to its first text baseline (its ascent).
    private struct Measured {
        let size: CGSize
        let ascent: CGFloat
    }

    /// A wrapped row: the indices it contains, its shared ascent/descent, and the
    /// total advance width (including inter-item spacing).
    private struct Row {
        var indices: [Int] = []
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat { ascent + descent }
    }

    private func measure(_ subviews: Subviews) -> [Measured] {
        subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            // `dimensions[.firstTextBaseline]` is the baseline distance from the
            // top. For a Text it is the font ascent; for a baseline-reporting
            // view (our MathView) it is the math height; for a view with no text
            // baseline SwiftUI returns the bottom edge, which falls back to
            // bottom-alignment — acceptable as a last resort.
            let dims = subview.dimensions(in: .unspecified)
            let ascent = dims[.firstTextBaseline]
            return Measured(size: size, ascent: ascent)
        }
    }

    private func rows(_ measured: [Measured], maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (i, m) in measured.enumerated() {
            let w = m.size.width
            if !current.indices.isEmpty, current.width + w > maxWidth {
                rows.append(current)
                current = Row()
            }
            if !current.indices.isEmpty { current.width += hSpacing }
            current.indices.append(i)
            current.width += w
            current.ascent = max(current.ascent, m.ascent)
            current.descent = max(current.descent, m.size.height - m.ascent)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let measured = measure(subviews)
        let laidOut = rows(measured, maxWidth: maxWidth)
        let widest = laidOut.map(\.width).max() ?? 0
        let totalHeight = laidOut.reduce(0) { $0 + $1.height }
            + vSpacing * CGFloat(max(0, laidOut.count - 1))
        let width = proposal.width.map { Swift.min(widest, $0) } ?? widest
        return CGSize(width: max(0, width), height: max(0, totalHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let measured = measure(subviews)
        let laidOut = rows(measured, maxWidth: bounds.width)
        var y = bounds.minY
        for row in laidOut {
            var x = bounds.minX
            let rowBaseline = y + row.ascent
            for index in row.indices {
                let m = measured[index]
                // Align each child on the shared baseline: its top sits at the
                // row baseline minus its own ascent.
                let top = rowBaseline - m.ascent
                subviews[index].place(
                    at: CGPoint(x: x, y: top),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(m.size)
                )
                x += m.size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }
}
