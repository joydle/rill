import RillCore
import RillAnalytics

/// Computes, for a document update, how many blocks SwiftUI will actually
/// re-render versus skip via stable-identity (`Equatable`) gating.
///
/// `EquatableBlockView` compares blocks by ``NodeID``; SwiftUI skips the body of
/// any block whose identity is unchanged from the previous render. This plan
/// mirrors that decision purely from the model so `DocumentView` can emit
/// accurate ``RenderMetrics`` — and so tests can prove tail-only re-rendering
/// headlessly, without pixels.
///
/// A block is *skipped* when a block with the same ``Block/id`` appeared in the
/// previous document; otherwise it is *rendered*. For append-only streaming, the
/// committed prefix keeps identical ids, so only the newly appended (or mutated)
/// tail blocks count as rendered.
enum DocumentRenderPlan {

    /// Builds render metrics for a transition from `previous` to `current`.
    /// - Parameters:
    ///   - previous: The document rendered on the prior pass, or `nil` for the
    ///     first render (every block then counts as rendered).
    ///   - current: The document being rendered now.
    /// - Returns: ``RenderMetrics`` with `blocksRendered` + `blocksSkipped`
    ///   accounting for every block in `current`, computed structurally by
    ///   diffing against `previous`.
    static func metrics(previous: Document?, current: Document) -> RenderMetrics {
        var priorIDs = Multiset<NodeID>()
        if let previous {
            for block in previous.blocks { priorIDs.insert(block.id) }
        }

        var rendered = 0
        var skipped = 0
        for block in current.blocks {
            if priorIDs.remove(block.id) {
                skipped += 1
            } else {
                rendered += 1
            }
        }

        return RenderMetrics(
            blocksRendered: rendered,
            blocksSkipped: skipped
        )
    }
}

/// A tiny counted set so repeated identical sibling blocks (e.g. two empty
/// thematic breaks) are matched one-for-one rather than all collapsing to a
/// single skip.
private struct Multiset<Element: Hashable> {
    private var counts: [Element: Int] = [:]

    mutating func insert(_ element: Element) {
        counts[element, default: 0] += 1
    }

    /// Removes one occurrence; returns `true` if one was present.
    mutating func remove(_ element: Element) -> Bool {
        guard let count = counts[element], count > 0 else { return false }
        if count == 1 {
            counts[element] = nil
        } else {
            counts[element] = count - 1
        }
        return true
    }
}
