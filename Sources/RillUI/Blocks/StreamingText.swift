import SwiftUI

/// The SwiftUI-native append reveal for the live streaming tail.
///
/// `StreamingText` renders a tail block's plain styled text and, whenever that
/// text grows, fades the newly appended run in at word granularity. The reveal
/// is driven entirely by a `withAnimation` transaction fired from `onChange` of
/// the text itself — i.e. tied to the document update from the incremental
/// parser — never by a per-character timer. It is pure SwiftUI and
/// cross-platform (iOS and macOS), with no external dependencies.
///
/// Only the active tail block is ever rendered through this view (see
/// ``TailAnimationPlan``); committed blocks render as static ``SwiftUI/Text`` and
/// are `Equatable`-gated, so a frozen block never re-evaluates and never
/// animates.
struct StreamingText: View {
    /// The fully styled text of the tail block.
    let text: AttributedString
    /// The base font for the text.
    let font: Font
    /// The base foreground color.
    let color: Color
    /// The reveal style (already guaranteed non-`.none` by the caller).
    let style: RenderConfig.AppendAnimation
    /// The reveal duration in seconds.
    let duration: TimeInterval

    /// The character offset where the currently-animating appended run begins.
    @State private var appendedFrom: Int = 0
    /// The reveal progress for the appended run: `0` hidden → `1` fully shown.
    @State private var progress: Double = 1
    /// Whether the first frame has been seeded (so initial content shows fully
    /// rather than fading the whole block on appear).
    @State private var seeded = false

    var body: some View {
        AnimatedAppendText(
            base: text,
            appendedFrom: appendedFrom,
            style: style,
            color: color,
            font: font,
            progress: progress
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { seeded = true }
        .onChange(of: text) { oldText, newText in
            reveal(from: oldText, to: newText)
        }
    }

    /// Begins a word-granular reveal of the run appended between `oldText` and
    /// `newText`, driven by a single SwiftUI animation transaction.
    private func reveal(from oldText: AttributedString, to newText: AttributedString) {
        let oldCount = oldText.characters.count
        let newCount = newText.characters.count

        // Pure growth is the streaming case. Anything else (shrink, replace) just
        // snaps to the final state — no misleading fade on a structural change.
        guard style != .none, newCount > oldCount else {
            appendedFrom = newCount
            progress = 1
            return
        }

        appendedFrom = AppendReveal.wordStart(in: String(oldText.characters), atOrBefore: oldCount)
        progress = 0
        withAnimation(.easeOut(duration: duration)) {
            progress = 1
        }
    }
}

/// The animatable leaf that re-renders the tail text each frame as `progress`
/// interpolates, applying ``AppendReveal`` to dim the appended run. Conforming to
/// `Animatable` is what lets SwiftUI interpolate the reveal smoothly from the
/// parent's `withAnimation`, with no `Timer`/`CADisplayLink`.
private struct AnimatedAppendText: View, Animatable {
    var base: AttributedString
    var appendedFrom: Int
    var style: RenderConfig.AppendAnimation
    var color: Color
    var font: Font
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(
            AppendReveal.reveal(
                base,
                appendedFrom: appendedFrom,
                progress: progress,
                style: style,
                color: color
            )
        )
        .font(font)
        .foregroundStyle(color)
    }
}
