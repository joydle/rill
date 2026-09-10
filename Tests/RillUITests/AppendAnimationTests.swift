import XCTest
import SwiftUI
@testable import RillUI
import RillCore
import RillAnalytics

/// Tests for the streaming append-reveal animation: config plumbing, the
/// tail-only animation plan (committed blocks excluded), and the pure reveal
/// math that ``StreamingText`` drives from a SwiftUI animation transaction.
///
/// These run headlessly — no pixels, no timers. They assert on the configuration
/// that flows into the render context, on the value-type ``TailAnimationPlan``
/// decision, on the ``ParagraphView/Model`` flag, and on the deterministic
/// ``AppendReveal`` opacity/word math.
@MainActor
final class AppendAnimationTests: XCTestCase {

    // MARK: - Config plumbing

    /// The tasteful default is a word-granular reveal with a short duration.
    func testDefaultAppendAnimationIsWordFade() {
        XCTAssertEqual(RenderConfig.default.appendAnimation, .word)
        XCTAssertEqual(RenderConfig.default.appendAnimationDuration, 0.22, accuracy: 0.0001)
    }

    /// The append-animation knobs survive into the render context the block views
    /// read from.
    func testAppendAnimationConfigPlumbsThroughContext() {
        let config = RenderConfig(appendAnimation: .fade, appendAnimationDuration: 0.5)
        let context = BlockRenderContext(theme: .default, config: config, analytics: NoopAnalytics())
        XCTAssertEqual(context.config.appendAnimation, .fade)
        XCTAssertEqual(context.config.appendAnimationDuration, 0.5, accuracy: 0.0001)
    }

    /// `.none` is a first-class option that fully disables the reveal.
    func testAppendAnimationCanBeDisabled() {
        let config = RenderConfig(appendAnimation: .none)
        XCTAssertEqual(config.appendAnimation, .none)
    }

    // MARK: - Tail-only plan: committed blocks never animate

    /// Only the final (active tail) block animates; every committed block is
    /// excluded, and no block animates when the reveal is disabled.
    func testOnlyActiveTailAnimates() {
        let on = RenderConfig(appendAnimation: .word)
        let count = 4

        // Committed blocks (every non-final index) never animate.
        for index in 0..<(count - 1) {
            XCTAssertFalse(
                TailAnimationPlan.animatesBlock(at: index, count: count, config: on),
                "Committed block at \(index) must not animate."
            )
        }
        // The tail (last index) animates.
        XCTAssertTrue(TailAnimationPlan.animatesBlock(at: count - 1, count: count, config: on))
    }

    /// With the reveal disabled, even the tail does not animate.
    func testNoBlockAnimatesWhenDisabled() {
        let off = RenderConfig(appendAnimation: .none)
        let count = 3
        for index in 0..<count {
            XCTAssertFalse(TailAnimationPlan.animatesBlock(at: index, count: count, config: off))
        }
    }

    /// An empty document animates nothing.
    func testEmptyDocumentAnimatesNothing() {
        let on = RenderConfig(appendAnimation: .word)
        XCTAssertFalse(TailAnimationPlan.animatesBlock(at: 0, count: 0, config: on))
    }

    // MARK: - Paragraph view-model flag

    /// The committed-vs-tail decision is also surfaced on the paragraph view
    /// model: a committed paragraph never animates; the tail animates only when
    /// enabled.
    func testParagraphModelAnimatesAppendFlag() {
        let paragraph = Paragraph(inlines: [.text("streaming tail")])
        let word = RenderConfig(appendAnimation: .word)
        let none = RenderConfig(appendAnimation: .none)

        // Committed block: never animates, regardless of config.
        let committed = ParagraphView.Model(
            paragraph: paragraph, theme: .default, config: word, isActiveTail: false
        )
        XCTAssertFalse(committed.animatesAppend, "Committed paragraphs must never animate.")

        // Active tail + enabled: animates.
        let tail = ParagraphView.Model(
            paragraph: paragraph, theme: .default, config: word, isActiveTail: true
        )
        XCTAssertTrue(tail.animatesAppend)

        // Active tail + disabled: does not animate.
        let tailOff = ParagraphView.Model(
            paragraph: paragraph, theme: .default, config: none, isActiveTail: true
        )
        XCTAssertFalse(tailOff.animatesAppend)
    }

    /// The default `isActiveTail` is `false` so static (non-streaming) renders
    /// never animate.
    func testParagraphModelDefaultsToCommitted() {
        let paragraph = Paragraph(inlines: [.text("static")])
        let model = ParagraphView.Model(paragraph: paragraph, theme: .default, config: .default)
        XCTAssertFalse(model.animatesAppend)
    }

    // MARK: - Pure reveal opacity math

    /// `.none` is fully opaque always; `.fade` tracks progress uniformly.
    func testOpacityNoneAndFade() {
        XCTAssertEqual(AppendReveal.opacity(style: .none, progress: 0, wordIndex: 0, wordCount: 3), 1)
        XCTAssertEqual(AppendReveal.opacity(style: .fade, progress: 0, wordIndex: 0, wordCount: 3), 0)
        XCTAssertEqual(AppendReveal.opacity(style: .fade, progress: 0.4, wordIndex: 2, wordCount: 3), 0.4, accuracy: 0.0001)
        XCTAssertEqual(AppendReveal.opacity(style: .fade, progress: 1, wordIndex: 0, wordCount: 3), 1)
    }

    /// `.word` sweeps the reveal left-to-right: at mid-progress, earlier words are
    /// fully shown and later words are still hidden.
    func testOpacityWordSweepsLeftToRight() {
        // 4 words, progress = 0.5 → first two words fully revealed, last two hidden.
        XCTAssertEqual(AppendReveal.opacity(style: .word, progress: 0.5, wordIndex: 0, wordCount: 4), 1)
        XCTAssertEqual(AppendReveal.opacity(style: .word, progress: 0.5, wordIndex: 1, wordCount: 4), 1)
        XCTAssertEqual(AppendReveal.opacity(style: .word, progress: 0.5, wordIndex: 2, wordCount: 4), 0)
        XCTAssertEqual(AppendReveal.opacity(style: .word, progress: 0.5, wordIndex: 3, wordCount: 4), 0)

        // A later word is partway through its own slice.
        let mid = AppendReveal.opacity(style: .word, progress: 0.625, wordIndex: 2, wordCount: 4)
        XCTAssertEqual(mid, 0.5, accuracy: 0.0001)
    }

    // MARK: - Word indexing & boundary snapping

    /// Each character maps to its word index; whitespace joins the preceding word.
    func testWordIndices() {
        XCTAssertEqual(AppendReveal.wordIndices("ab cd"), [0, 0, 0, 1, 1])
        // Leading whitespace maps to word 0; the first real word is still 0.
        XCTAssertEqual(AppendReveal.wordIndices(" a"), [0, 0])
        // A space between words belongs to the preceding word.
        XCTAssertEqual(AppendReveal.wordIndices("a b"), [0, 0, 1])
        XCTAssertEqual(AppendReveal.wordIndices(""), [])
    }

    /// The appended region snaps back to the start of the half-typed last word.
    func testWordStartSnapsToWordBoundary() {
        // "hello wor" — offset 9 is mid-"wor"; snap back to index 6.
        XCTAssertEqual(AppendReveal.wordStart(in: "hello wor", atOrBefore: 9), 6)
        // Offset right after a space stays put.
        XCTAssertEqual(AppendReveal.wordStart(in: "hello ", atOrBefore: 6), 6)
        // Within the first word snaps to 0.
        XCTAssertEqual(AppendReveal.wordStart(in: "hello", atOrBefore: 3), 0)
    }

    // MARK: - Reveal applies opacity only to the appended region

    /// `.none` and a completed reveal return the text untouched.
    func testRevealNoOpCases() {
        let base = AttributedString("hello world")
        XCTAssertEqual(
            AppendReveal.reveal(base, appendedFrom: 6, progress: 0, style: .none, color: .red), base
        )
        XCTAssertEqual(
            AppendReveal.reveal(base, appendedFrom: 6, progress: 1, style: .word, color: .red), base
        )
    }

    /// At the start of a reveal, the stable prefix keeps its (absent) color while
    /// the appended run is tinted — proving only the tail's new text is affected.
    func testRevealTintsOnlyAppendedRun() {
        let base = AttributedString("hello world")
        let revealed = AppendReveal.reveal(
            base, appendedFrom: 6, progress: 0, style: .fade, color: .red
        )

        // Prefix character "h" (index 0): untouched, inherits the view color.
        XCTAssertNil(foregroundColor(of: revealed, at: 0))
        // Last prefix character (index 5, the space): also untouched.
        XCTAssertNil(foregroundColor(of: revealed, at: 5))
        // Appended character "w" (index 6): tinted by the reveal.
        XCTAssertNotNil(foregroundColor(of: revealed, at: 6))
        // Final character: tinted too.
        XCTAssertNotNil(foregroundColor(of: revealed, at: 10))
    }

    /// Reads the SwiftUI foreground color of a single character by offset.
    private func foregroundColor(of string: AttributedString, at offset: Int) -> Color? {
        let start = string.characters.index(string.characters.startIndex, offsetBy: offset)
        let end = string.characters.index(after: start)
        return string[start..<end].foregroundColor
    }
}
