import SwiftUI
import RillCore
import RillAnalytics

/// Renders a ``CodeBlock`` according to the theme's ``CodeBlockStyle``.
///
/// Two presentations are selectable via ``RillTheme/codeBlock``:
/// - ``CodeBlockStyle/inlineScrollable(maxPreviewLines:)`` — a horizontally
///   scrollable monospaced block that also scrolls vertically once the code
///   exceeds `maxPreviewLines`, capping how much of a long listing is shown
///   inline.
/// - ``CodeBlockStyle/tappableCard(maxPreviewLines:)`` — a truncated card
///   that expands to a full-screen viewer on tap.
///
/// In both cases tapping copy places the verbatim code on the pasteboard and
/// fires ``MarkdownInteraction/codeCopied(language:)`` through the context's
/// analytics sink. The displayed text is syntax-highlighted by a
/// ``CodeHighlighter`` (defaulting to ``RillSyntax``) whose token colors come
/// from the theme.
struct CodeBlockView: View {
    /// The code block to render.
    let codeBlock: CodeBlock

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// Whether the full-screen viewer (tappable-card style) is presented.
    @State private var isExpanded = false

    /// Height of one rendered code line, derived from real font metrics rather
    /// than a hardcoded constant: it tracks the resolved monospaced callout font
    /// (~21pt) and scales with Dynamic Type / accessibility sizes via
    /// `@ScaledMetric`, so the capped preview viewport never falls short of
    /// `maxPreviewLines` actual lines and clips the final line.
    @ScaledMetric(relativeTo: .callout) private var codeLineHeight: CGFloat = 21

    var body: some View {
        let model = Model(codeBlock: codeBlock, theme: context.theme)
        switch context.theme.codeBlock {
        case .inlineScrollable(let maxPreviewLines):
            inlineScrollable(model: model, maxPreviewLines: maxPreviewLines)
        case .tappableCard(let maxPreviewLines):
            tappableCard(model: model, maxPreviewLines: maxPreviewLines)
        }
    }

    /// The shared header: language tag plus copy button.
    @ViewBuilder
    private func header(_ model: Model) -> some View {
        HStack {
            if let language = model.language, !language.isEmpty {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(context.theme.colors.textSecondary)
            }
            Spacer()
            Button(action: performCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(context.theme.colors.textSecondary)
            .accessibilityLabel("Copy code")
        }
        .padding(.horizontal, context.theme.metrics.codePadding)
        .padding(.top, context.theme.metrics.codePadding / 2)
    }

    /// Inline, scrollable presentation; vertically capped at `maxPreviewLines`.
    @ViewBuilder
    private func inlineScrollable(model: Model, maxPreviewLines: Int) -> some View {
        let capped = model.lineCount > maxPreviewLines
        VStack(alignment: .leading, spacing: 0) {
            header(model)
            ScrollView(capped ? [.horizontal, .vertical] : [.horizontal], showsIndicators: false) {
                Text(model.displayText)
                    .font(context.theme.fonts.code)
                    .foregroundStyle(context.theme.colors.textPrimary)
                    .padding(context.theme.metrics.codePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: capped ? previewHeight(maxPreviewLines) : nil)
        }
        .background(context.theme.colors.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: context.theme.metrics.codeCornerRadius))
    }

    /// Truncated card presentation; tapping expands to a full-screen viewer.
    @ViewBuilder
    private func tappableCard(model: Model, maxPreviewLines: Int) -> some View {
        Button {
            isExpanded = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                header(model)
                // Do NOT nest the preview in a horizontal ScrollView: the card is
                // a fixed-width affordance that expands on tap. Letting the Text
                // clip to the card's bounded width makes `.truncationMode(.tail)`
                // actually engage for both excess lines and over-wide lines,
                // instead of the scroll view proposing unbounded width (which
                // makes truncation dead code and lets one long line extend the
                // card arbitrarily).
                Text(model.displayText)
                    .font(context.theme.fonts.code)
                    .foregroundStyle(context.theme.colors.textPrimary)
                    .lineLimit(maxPreviewLines)
                    .truncationMode(.tail)
                    .padding(context.theme.metrics.codePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.exceedsPreview(maxLines: maxPreviewLines) {
                    Text("Tap to expand")
                        .font(.caption)
                        .foregroundStyle(context.theme.colors.link)
                        .padding(.horizontal, context.theme.metrics.codePadding)
                        .padding(.bottom, context.theme.metrics.codePadding / 2)
                }
            }
        }
        .buttonStyle(.plain)
        .background(context.theme.colors.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: context.theme.metrics.codeCornerRadius))
        .sheet(isPresented: $isExpanded) {
            CodeFullScreenView(model: model, context: context, onCopy: performCopy)
        }
    }

    /// The capped preview height for `lines` of code (plus block padding).
    private func previewHeight(_ lines: Int) -> CGFloat {
        CGFloat(lines) * codeLineHeight + context.theme.metrics.codePadding * 2
    }

    /// Copies the code and reports the interaction. Internal so headless tests
    /// can invoke it without simulating a tap.
    func performCopy() {
        Pasteboard.copy(codeBlock.content)
        context.analytics.didInteract(.codeCopied(language: codeBlock.language))
    }

    /// The render-independent view model for a code block. Exposed for headless
    /// assertions.
    struct Model {
        /// The optional language tag.
        let language: String?
        /// The text to display (verbatim code in v1).
        let displayText: AttributedString
        /// The exact payload placed on the pasteboard by the copy button.
        let copyText: String
        /// The number of lines in the code block.
        let lineCount: Int
        /// The character length of the longest line, used to detect a card
        /// preview that would overflow horizontally even with few lines.
        let maxLineCharacters: Int

        /// Builds a code-block model from its block and theme, syntax-highlighting
        /// the content with the supplied highlighter (``RillSyntax`` by default).
        /// - Parameters:
        ///   - codeBlock: The code block to render.
        ///   - theme: The theme supplying the code font and syntax palette.
        ///   - highlighter: The highlighter to colorize the content. Pass a
        ///     shared instance to reuse its cache across rebuilds during
        ///     streaming; defaults to a fresh ``RillSyntax`` bound to `theme`.
        init(codeBlock: CodeBlock, theme: RillTheme, highlighter: CodeHighlighter? = nil) {
            self.language = codeBlock.language
            self.copyText = codeBlock.content
            let resolved = highlighter ?? RillSyntax(theme: theme)
            self.displayText = resolved.highlight(codeBlock.content, language: codeBlock.language)
            // A trailing newline does not introduce an extra logical line.
            let trimmed = codeBlock.content.hasSuffix("\n")
                ? String(codeBlock.content.dropLast())
                : codeBlock.content
            let lines = trimmed.isEmpty ? [] : trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            self.lineCount = lines.count
            self.maxLineCharacters = lines.map(\.count).max() ?? 0
        }

        /// The character budget above which a single preview line is treated as
        /// likely to overflow the card's bounded width (and so warrants the
        /// "Tap to expand" hint even when the line count fits).
        static let previewCharacterBudget = 60

        /// Whether the card preview should advertise expansion: either the listing
        /// has more lines than the preview shows, or its widest line is long enough
        /// to be truncated horizontally.
        func exceedsPreview(maxLines: Int) -> Bool {
            lineCount > maxLines || maxLineCharacters > Self.previewCharacterBudget
        }
    }
}

/// The full-screen code viewer presented when a ``CodeBlockStyle/tappableCard``
/// code block is tapped: the complete, selectable listing with copy and close
/// actions.
private struct CodeFullScreenView: View {
    /// The code-block model supplying the highlighted text.
    let model: CodeBlockView.Model
    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext
    /// Copies the code and reports the interaction (same path as the card).
    let onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(model.displayText)
                .font(context.theme.fonts.code)
                .foregroundStyle(context.theme.colors.textPrimary)
                .textSelection(.enabled)
                .padding(context.theme.metrics.codePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(context.theme.colors.codeBackground)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 16) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy code")
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel("Close")
            }
            .padding()
            .foregroundStyle(context.theme.colors.textSecondary)
        }
    }
}
