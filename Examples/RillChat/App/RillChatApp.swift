import SwiftUI

/// A tiny AI-chat client built on Rill. Pick the experience with the launch
/// argument `RILL_SCENE` (`coding` · `math` · `docs`) so each can be recorded.
@main
struct RillChatApp: App {
    var body: some Scene {
        WindowGroup {
            let scene = ProcessInfo.processInfo.environment["RILL_SCENE"] ?? "coding"
            let convo = Conversation.named(scene)
            ChatView(convo)
                .preferredColorScheme(convo.palette.scheme)
        }
    }
}
