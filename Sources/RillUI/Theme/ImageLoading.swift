import SwiftUI

/// An asynchronous image source injected through ``RenderConfig``.
///
/// `ImageLoading` lets the host supply its own image pipeline (a host injects
/// a Nuke-backed adapter) without RillUI taking a dependency on it. Conformers
/// must be `Sendable` so they can be captured by the value-type ``RenderConfig``
/// and used across concurrency domains. The returned value is a SwiftUI
/// ``SwiftUI/Image`` ready to place in the view tree; throwing or returning a
/// failure lets the renderer fall back to the image's alt text.
public protocol ImageLoading: Sendable {
    /// Loads the image at the given URL.
    /// - Parameter url: The fully-qualified source URL.
    /// - Returns: A ready-to-display SwiftUI image.
    /// - Throws: Any error from the underlying pipeline; the renderer treats a
    ///   thrown error as a load failure and shows alt text.
    func image(for url: URL) async throws -> Image
}
