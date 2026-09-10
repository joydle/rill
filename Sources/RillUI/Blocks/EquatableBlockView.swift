import SwiftUI
import RillCore

/// A block view wrapped with stable-identity gating so unchanged committed
/// blocks are skipped by SwiftUI.
///
/// `EquatableBlockView` renders a single ``Block`` and conforms to `Equatable`
/// **by the block's ``NodeID`` alone**. Because the incremental parser keeps a
/// committed block's `NodeID` byte-stable across streamed deltas, two
/// `EquatableBlockView`s for the same committed block compare equal — so when
/// `DocumentView` applies `.equatable()`, SwiftUI elides their `body`
/// evaluation entirely. Only the live tail block (whose content, and thus
/// `NodeID`, changed) re-renders. This is the streaming-smoothness win described
/// in the design's "stable-identity rendering".
///
/// The render environment (``BlockRenderContext``) is intentionally excluded
/// from equality: the theme/config/analytics do not change per delta during a
/// stream, and including them would defeat skipping.
public struct EquatableBlockView: View, Equatable {
    /// The block to render.
    let block: Block

    /// The shared theme/config/analytics environment.
    let context: BlockRenderContext

    /// Whether this is the active streaming tail block. Deliberately excluded
    /// from `==` (below): a block that has just committed keeps its byte-stable
    /// ``NodeID`` and so is skipped, freezing at its final fully-revealed state —
    /// exactly the "committed blocks never animate" guarantee.
    let isActiveTail: Bool

    /// Creates an equatable block view.
    /// - Parameters:
    ///   - block: The block to render.
    ///   - context: The shared theme/config/analytics environment.
    ///   - isActiveTail: Whether this is the live streaming tail block. Defaults
    ///     to `false`.
    public init(block: Block, context: BlockRenderContext, isActiveTail: Bool = false) {
        self.block = block
        self.context = context
        self.isActiveTail = isActiveTail
    }

    /// Wraps the block's ``BlockView`` in an `EquatableView` so SwiftUI can skip
    /// re-rendering committed blocks whose ``NodeID`` is unchanged.
    public var body: some View {
        EquatableView(content: BlockView(block: block, context: context, isActiveTail: isActiveTail))
    }

    /// Equal when the blocks share a ``NodeID``. SwiftUI uses this to skip the
    /// body of an unchanged committed block.
    public nonisolated static func == (lhs: EquatableBlockView, rhs: EquatableBlockView) -> Bool {
        lhs.block.id == rhs.block.id
    }
}

extension BlockView: Equatable {
    /// `BlockView` compares by block identity so `EquatableView` can gate it.
    nonisolated static func == (lhs: BlockView, rhs: BlockView) -> Bool {
        lhs.block.id == rhs.block.id
    }
}
