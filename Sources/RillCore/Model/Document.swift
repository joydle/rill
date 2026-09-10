/// A parsed Markdown document: an ordered list of block-level nodes.
///
/// `Document` is the root of the RillCore AST and a `Sendable`, `Hashable`
/// value type. The incremental parser publishes a fresh `Document` on each
/// streamed delta; committed blocks keep stable ``Block/id`` values across
/// deltas so SwiftUI diffing stays cheap.
public struct Document: Sendable, Hashable {
    /// The document's block-level content, in order.
    public var blocks: [Block]

    /// Creates a document.
    /// - Parameter blocks: The document's block-level content.
    public init(blocks: [Block]) {
        self.blocks = blocks
    }
}
