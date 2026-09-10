import SwiftUI

/// Pure, headlessly-testable math for the streaming append reveal.
///
/// `AppendReveal` computes which characters of a tail block's styled text are
/// "newly appended" and how visible each should be at a given animation
/// `progress` (0 → fully hidden, 1 → fully shown). It owns no view state and
/// touches no timers — ``StreamingText`` drives `progress` from a SwiftUI
/// `withAnimation` transaction tied to the document update, so the reveal rides
/// the parser's own update cadence instead of fighting it.
///
/// The split is at *word* granularity: when text changes, the appended region is
/// snapped back to the start of the last (possibly half-typed) word so a word
/// reveals as a unit rather than character-by-character. The reveal is
/// SwiftUI-native and requires no external dependencies.
enum AppendReveal {

    /// Returns `base` with characters from `startOffset` onward dimmed according
    /// to `progress` and `style`. Characters before `startOffset` (the stable
    /// prefix) are untouched and inherit the view's foreground style.
    ///
    /// - Parameters:
    ///   - base: The fully styled attributed text of the tail block.
    ///   - startOffset: The character offset where the newly appended run begins.
    ///   - progress: The reveal progress, clamped to `0…1`.
    ///   - style: The reveal style. ``RenderConfig/AppendAnimation/none`` and a
    ///     completed (`progress >= 1`) reveal return `base` unchanged.
    ///   - color: The base foreground color, used to tint appended characters
    ///     that carry no explicit color of their own.
    /// - Returns: The attributed string with per-character opacity applied to the
    ///   appended region.
    static func reveal(
        _ base: AttributedString,
        appendedFrom startOffset: Int,
        progress: Double,
        style: RenderConfig.AppendAnimation,
        color: Color
    ) -> AttributedString {
        guard style != .none, progress < 1 else { return base }

        let total = base.characters.count
        let start = max(0, min(startOffset, total))
        guard start < total else { return base }

        let appendedString = String(
            base.characters[base.characters.index(base.characters.startIndex, offsetBy: start)...]
        )
        let wordIndex = wordIndices(appendedString)
        let wordCount = (wordIndex.max() ?? -1) + 1

        var result = base
        var index = result.characters.index(result.characters.startIndex, offsetBy: start)
        var position = 0
        while index < result.characters.endIndex {
            let next = result.characters.index(after: index)
            let alpha = opacity(
                style: style,
                progress: progress,
                wordIndex: wordIndex[position],
                wordCount: wordCount
            )
            let existing = result[index..<next].foregroundColor ?? color
            result[index..<next].foregroundColor = existing.opacity(alpha)
            index = next
            position += 1
        }
        return result
    }

    /// The per-character opacity for an appended character.
    static func opacity(
        style: RenderConfig.AppendAnimation,
        progress: Double,
        wordIndex: Int,
        wordCount: Int
    ) -> Double {
        let p = max(0, min(1, progress))
        switch style {
        case .none:
            return 1
        case .fade:
            return p
        case .word:
            guard wordCount > 0 else { return p }
            // Sweep the reveal left-to-right: word k occupies the progress slice
            // [k/wordCount, (k+1)/wordCount]. Within its slice it ramps 0 → 1.
            let span = 1.0 / Double(wordCount)
            let local = (p - Double(wordIndex) * span) / span
            return max(0, min(1, local))
        }
    }

    /// Assigns a zero-based word index to every character of `string`. Whitespace
    /// is attributed to the preceding word so a word and its trailing space
    /// reveal together; leading whitespace maps to word `0`.
    static func wordIndices(_ string: String) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(string.count)
        var current = -1
        var prevWasWhitespace = true
        for character in string {
            let isWhitespace = character.isWhitespace
            if !isWhitespace && prevWasWhitespace {
                current += 1
            }
            out.append(max(0, current))
            prevWasWhitespace = isWhitespace
        }
        return out
    }

    /// Snaps `offset` back to the start of the word it falls in: the largest
    /// index `≤ offset` whose preceding character is whitespace. This makes the
    /// last (possibly half-typed) word of the previous frame re-reveal as a whole
    /// once it finishes, instead of the new characters fading in mid-word.
    static func wordStart(in string: String, atOrBefore offset: Int) -> Int {
        let characters = Array(string)
        var index = max(0, min(offset, characters.count))
        while index > 0 && !characters[index - 1].isWhitespace {
            index -= 1
        }
        return index
    }
}

/// Decides which block in a streamed document is the *active tail* — the one
/// still receiving characters and therefore the only one allowed to animate its
/// appended text.
///
/// This is the load-bearing rule behind "committed blocks never animate": the
/// incremental parser freezes every block before the last into a byte-stable
/// committed prefix, so the active tail is always the final block. Pulling the
/// decision into a tiny pure value type lets headless tests assert it directly,
/// without rendering pixels.
public enum TailAnimationPlan {

    /// Whether the block at `index` (within `count` blocks) should animate its
    /// appended text under `config`.
    ///
    /// Returns `true` only for the last block, and only when
    /// ``RenderConfig/appendAnimation`` is not ``RenderConfig/AppendAnimation/none``.
    /// Every committed block (any non-final index) returns `false`, as does every
    /// block when the animation is disabled.
    ///
    /// - Parameters:
    ///   - index: The block's position in the document.
    ///   - count: The total number of blocks in the document.
    ///   - config: The render configuration.
    /// - Returns: `true` if the block is the animating active tail.
    public static func animatesBlock(at index: Int, count: Int, config: RenderConfig) -> Bool {
        guard config.appendAnimation != .none, count > 0 else { return false }
        return index == count - 1
    }
}
