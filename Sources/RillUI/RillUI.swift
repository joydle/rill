// Re-export the analytics and math layers so `import RillUI` is enough to use
// the documented rendering + analytics surface: `MarkdownAnalytics`,
// `ParseMetrics`, `RenderMetrics`, `MarkdownInteraction`, and the sinks come from
// RillAnalytics; the math model from RillMath. RillCore is intentionally NOT
// re-exported: its `Image`/`List`/`Table`/`Link`/`Alert` model types collide with
// SwiftUI's, so consumers that touch the parsed `Document` AST directly should
// `import RillCore` explicitly (and use its `InlineImage`/`MarkdownList`/… aliases
// to disambiguate).
@_exported import RillAnalytics
@_exported import RillMath

/// Namespace and version metadata for the RillUI module.
///
/// RillUI is the SwiftUI layer that renders the AST into views, applies
/// theming, draws math, and highlights code. It depends on RillCore,
/// RillMath, and RillAnalytics and is the only module permitted to import
/// SwiftUI or UIKit.
public enum RillUI: Sendable {
    /// The semantic version of the Rill package.
    public static let version = "1.0.0"
}
