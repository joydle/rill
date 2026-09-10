/// Namespace and version metadata for the RillCore module.
///
/// RillCore is the Foundation-only layer that owns the Markdown AST and the
/// incremental, stable-prefix streaming parser. It must never import SwiftUI
/// or UIKit; that boundary is enforced by ``LayeringGuardTests``.
public enum RillCore: Sendable {
    /// The semantic version of the Rill package.
    public static let version = "1.0.0"
}
