import SwiftUI

/// iOS Simulator host for the Rill streaming demo.
///
/// The demo UI and logic live in the `RillDemoKit` sources (compiled directly
/// into this app target): the chunked-streaming simulator, the analytics HUD,
/// the showcase document, the theme catalog, and ``DemoRootView``. This file is
/// only the `@main` entry point that mounts the root view in a window.
@main
struct RillDemoiOSApp: App {
    var body: some Scene {
        WindowGroup {
            // Visual-QA mode: when RILL_QA_CASE is set, render that single case
            // full-screen for screenshot inspection. Otherwise, the live demo.
            if let raw = ProcessInfo.processInfo.environment["RILL_QA_CASE"],
               let index = Int(raw) {
                QACaseView(QACatalog.case(at: index))
            } else {
                DemoRootView()
            }
        }
    }
}
