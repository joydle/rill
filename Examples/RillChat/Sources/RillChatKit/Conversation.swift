import SwiftUI

/// One scripted turn: a user prompt and the assistant's full Markdown answer,
/// streamed token-by-token by ``ChatView``.
public struct Conversation: Sendable {
    public var title: String
    public var subtitle: String
    public var palette: Palette
    public var rounded: Bool
    public var prompt: String
    public var answer: String

    /// The three example experiences, keyed by an id (also used as the launch
    /// argument `RILL_SCENE` so each can be recorded on its own).
    public static func named(_ id: String) -> Conversation {
        switch id {
        case "math":  return math
        case "docs":  return docs
        default:       return coding
        }
    }

    public static let coding = Conversation(
        title: "Rill", subtitle: "streaming markdown · SwiftUI",
        palette: .dark, rounded: false,
        prompt: "How do I render a streaming LLM reply in SwiftUI?",
        answer: """
        Drive a `MarkdownSource` and append tokens as they arrive — Rill re-parses \
        only the **dirty tail**, so a long reply stays smooth no matter how far it grows.

        ```swift
        @State var source = MarkdownSource()

        var body: some View {
          StreamingMarkdownView(source)
            .task {
              for await t in llm(prompt) {
                source.append(t)
              }
            }
        }
        ```

        Committed blocks are `Equatable`-skipped, so only the live tail redraws.
        """)

    public static let math = Conversation(
        title: "Rill", subtitle: "native TeX math · CoreText",
        palette: .dark, rounded: false,
        prompt: "State Maxwell's equations in differential form.",
        answer: """
        The four **Maxwell equations** in differential form:

        $$\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}$$

        $$\\nabla \\times \\mathbf{B} = \\mu_0 \\mathbf{J} + \\mu_0 \\varepsilon_0 \\frac{\\partial \\mathbf{E}}{\\partial t}$$

        Together with $\\nabla \\cdot \\mathbf{B} = 0$ and Faraday's law, they unify \
        electricity, magnetism, and light.
        """)

    public static let docs = Conversation(
        title: "Rill", subtitle: "custom theme · GFM",
        palette: .light, rounded: true,
        prompt: "How does Rill compare on a 64 KB reply?",
        answer: """
        Cumulative parse time for a 64 KB streamed reply, measured on one
        machine [^1]:

        | Renderer | Parse time | vs Rill |
        | --- | ---: | ---: |
        | **Rill** | 9.0 ms | — |
        | MarkdownUI | 144 ms | 16× |
        | swift-markdown | 443 ms | 49× |

        > [!NOTE]
        > Per-delta cost stays proportional to the dirty tail, so the ratio
        > grows with the length of the reply.

        [^1]: `O(tail)` instead of `O(document)`. See `Benchmarks/RESULTS.md`.
        """)
}
