/// Namespace and version metadata for the RillAnalytics module.
///
/// RillAnalytics is the Foundation-only layer that defines the analytics
/// protocol, metrics value types, and sinks. It must never import SwiftUI or
/// UIKit; that boundary is enforced by ``LayeringGuardTests``.
public enum RillAnalytics: Sendable {
    /// The semantic version of the Rill package.
    public static let version = "1.0.0"
}
