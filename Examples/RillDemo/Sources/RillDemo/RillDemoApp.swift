import SwiftUI
import RillDemoKit

/// The thin `@main` host for the Rill streaming demo.
///
/// All of the demo's logic lives in `RillDemoKit` (the streaming simulator, the
/// analytics HUD sink, the showcase document, the theme catalog, and the SwiftUI
/// views) so it can be exercised headlessly under `swift test`. This executable
/// only mounts ``DemoRootView`` in a window.
@main
struct RillDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoRootView()
        }
    }
}
