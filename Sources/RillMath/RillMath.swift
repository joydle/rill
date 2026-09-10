/// Namespace and version metadata for the RillMath module.
///
/// RillMath is the Foundation-only layer that tokenizes LaTeX and lays it out
/// into a TeX-style box tree. It must never import SwiftUI or UIKit; that
/// boundary is enforced by ``LayeringGuardTests``.
public enum RillMath: Sendable {
    /// The semantic version of the Rill package.
    public static let version = "1.0.0"
}
