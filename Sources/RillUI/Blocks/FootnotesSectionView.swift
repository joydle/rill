import SwiftUI
import RillCore

/// Renders the document's footnotes as a numbered section at the very end.
///
/// `DocumentView` appends one of these after the main block flow when the
/// document defines any footnotes. Each entry shows its 1-based number beside the
/// definition's rendered blocks, matching the superscript markers
/// ``FootnoteReferenceView`` draws inline. A leading divider separates the section
/// from the body.
struct FootnotesSectionView: View {
    /// The shared theme/config/analytics environment, carrying the footnote
    /// ``FootnoteRegistry`` whose entries this view lays out.
    let context: BlockRenderContext

    var body: some View {
        let entries = context.footnotes.entries
        VStack(alignment: .leading, spacing: context.theme.metrics.paragraphSpacing) {
            Divider()
                .overlay(context.theme.colors.tableBorder)
            Text("Footnotes")
                .font(.headline)
                .foregroundStyle(context.theme.colors.textSecondary)
            ForEach(entries, id: \.number) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(entry.number).")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.theme.colors.citation)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                            BlockView(block: block, context: context)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders a footnote reference (`[^id]`) as a tappable superscript number.
///
/// A footnote reference is parsed as a ``Citation`` with a `nil` index; when its
/// marker resolves in the context's ``FootnoteRegistry``, the inline renderer
/// draws this superscript marker instead of a ``CitationPill``. Tapping it fires
/// ``MarkdownInteraction/citationTapped(marker:index:)`` — reusing the existing
/// citation interaction analytics — with the resolved footnote number as the
/// index.
struct FootnoteReferenceView: View {
    /// The reference citation (its marker matches a footnote definition).
    let citation: Citation

    /// The resolved 1-based footnote number.
    let number: Int

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    var body: some View {
        Button(action: performTap) {
            Text("\(number)")
                .font(.caption2.weight(.semibold))
                .baselineOffset(6)
                .foregroundStyle(context.theme.colors.citation)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Footnote \(number)")
    }

    /// Reports the footnote tap. Internal so headless tests can invoke it without
    /// simulating a touch. Fires
    /// ``MarkdownInteraction/citationTapped(marker:index:)`` with the footnote
    /// number as the index.
    func performTap() {
        context.analytics.didInteract(
            .citationTapped(marker: citation.marker, index: number)
        )
    }
}
