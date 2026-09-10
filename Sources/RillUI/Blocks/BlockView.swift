import SwiftUI
import RillCore

/// Renders a single ``Block`` by dispatching to the appropriate per-kind view.
///
/// `BlockView` is the switchboard over the `Block` enum: it maps each case to
/// its dedicated view (``HeadingView``, ``ParagraphView``, ``QuoteView``,
/// ``ListView``, ``CodeBlockView``, ``TableView``, ``ThematicBreakView``,
/// ``MathBlockView``, ``HTMLBlockView``). It is wrapped by ``EquatableBlockView``
/// so that committed blocks with unchanged identity skip re-rendering.
struct BlockView: View {
    /// The block to render.
    let block: Block

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// Whether this block is the active streaming tail. Only the tail's text
    /// renderers animate appended text; committed blocks render statically.
    var isActiveTail: Bool = false

    var body: some View {
        switch block {
        case .heading(let heading):
            HeadingView(heading: heading, context: context, isActiveTail: isActiveTail)
        case .paragraph(let paragraph):
            ParagraphView(paragraph: paragraph, context: context, isActiveTail: isActiveTail)
        case .blockQuote(let quote):
            QuoteView(quote: quote, context: context)
        case .alert(let alert):
            AlertView(alert: alert, context: context)
        case .list(let list):
            ListView(list: list, context: context)
        case .codeBlock(let codeBlock):
            CodeBlockView(codeBlock: codeBlock, context: context)
        case .table(let table):
            TableView(table: table, context: context)
        case .thematicBreak:
            ThematicBreakView(theme: context.theme)
        case .mathBlock(let mathBlock):
            MathBlockView(mathBlock: mathBlock, theme: context.theme)
        case .htmlBlock(let html):
            HTMLBlockView(html: html, theme: context.theme)
        case .footnoteDefinition:
            // Footnote definitions are collected and rendered together as a
            // numbered section at the end of the document (see
            // ``FootnotesSectionView``), not inline at their source position.
            EmptyView()
        }
    }
}
