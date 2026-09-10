import SwiftUI
import RillCore
import RillAnalytics

/// A tappable inline pill representing a ``Citation`` (e.g. `[1]` or `[^id]`).
///
/// The pill resolves its marker through ``RenderConfig/citationResolver`` once,
/// at construction, to derive its label and (optional) destination. Tapping it
/// fires ``MarkdownInteraction/citationTapped(marker:index:)`` through the
/// context's analytics sink. When the marker does not resolve, the pill still
/// renders its bare marker and a tap is still reported, but no host navigation
/// is implied. Resolution happens exactly once so repeatedly reading ``model``
/// (as SwiftUI does across body evaluations) never re-invokes the resolver.
struct CitationPill: View {
    /// The render-independent view model: the pill's label and resolved target.
    let model: Model

    /// The citation this pill represents.
    private let citation: Citation

    /// The shared theme/config/analytics environment.
    private let context: BlockRenderContext

    /// Creates a citation pill, resolving its target up front.
    /// - Parameters:
    ///   - citation: The citation to present.
    ///   - context: The render context supplying theme, config, and analytics.
    init(citation: Citation, context: BlockRenderContext) {
        self.citation = citation
        self.context = context
        self.model = Model(citation: citation, context: context)
    }

    var body: some View {
        Button(action: performTap) {
            Text(model.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(context.theme.colors.citation)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(context.theme.colors.citation.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
    }

    /// Reports the citation tap. Internal so headless tests can invoke it without
    /// simulating a touch. Fires ``MarkdownInteraction/citationTapped(marker:index:)``
    /// and opens the resolved destination through the host link handler when one
    /// exists.
    func performTap() {
        context.analytics.didInteract(
            .citationTapped(marker: citation.marker, index: citation.index)
        )
        if let urlString = model.target?.url,
           let url = URL(string: urlString),
           let handler = context.config.linkHandler {
            handler(url)
        }
    }

    /// The render-independent view model for a citation pill. Exposed for
    /// headless assertions and stable across body evaluations.
    struct Model {
        /// The text shown inside the pill (the bare marker, e.g. `1`).
        let label: AttributedString

        /// The resolved destination, or `nil` when the marker has no known
        /// source (the pill then renders but implies no navigation).
        let target: CitationTarget?

        /// The accessibility label, including the resolved source title when
        /// available.
        let accessibilityLabel: String

        /// Builds a pill model, resolving the marker exactly once.
        init(citation: Citation, context: BlockRenderContext) {
            self.label = AttributedString(citation.marker)
            self.target = context.config.citationResolver?(citation.marker)
            if let title = target?.title {
                self.accessibilityLabel = "Citation \(citation.marker): \(title)"
            } else {
                self.accessibilityLabel = "Citation \(citation.marker)"
            }
        }
    }
}
