/// A run of identical emphasis delimiter characters (`*`, `_`, or `~`) tracked
/// during inline parsing, annotated with CommonMark flanking information.
///
/// A delimiter run is the maximal sequence of the same delimiter character. Its
/// ``canOpen`` / ``canClose`` flags encode the CommonMark *left-flanking* and
/// *right-flanking* rules, which decide whether the run may begin or end an
/// emphasis span. ``count`` is consumed as emphasis spans are matched; when it
/// reaches zero the run is exhausted.
struct DelimiterRun {
    /// The delimiter character: `*`, `_`, or `~`.
    let char: Character

    /// The number of delimiter characters still available for matching.
    var count: Int

    /// Whether this run may open an emphasis span (is left-flanking, with the
    /// extra `_` intraword restriction already applied).
    let canOpen: Bool

    /// Whether this run may close an emphasis span (is right-flanking, with the
    /// extra `_` intraword restriction already applied).
    let canClose: Bool

    /// The index of the placeholder text node for this run within the inline
    /// node buffer, used to recover the literal text if the run goes unmatched.
    /// It shifts as the buffer is rewritten during emphasis resolution.
    var startIndex: Int

    /// The original delimiter count, retained for literal reconstruction.
    let originalCount: Int

    /// Creates a delimiter run.
    init(char: Character, count: Int, canOpen: Bool, canClose: Bool, startIndex: Int) {
        self.char = char
        self.count = count
        self.originalCount = count
        self.canOpen = canOpen
        self.canClose = canClose
        self.startIndex = startIndex
    }
}

/// A last-in-first-out stack of ``DelimiterRun`` values used by the inline
/// parser's CommonMark emphasis algorithm.
///
/// The stack records every potential emphasis opener/closer in source order. A
/// closing run scans backward through the stack for the nearest compatible
/// opener; unmatched runs that survive to the end of parsing are emitted as
/// literal text — which is precisely how an unbalanced trailing `**` in a
/// streaming tail degrades to plain text instead of flickering.
struct DelimiterStack {
    private var runs: [DelimiterRun] = []

    /// Creates an empty delimiter stack.
    init() {}

    /// The number of runs currently on the stack.
    var count: Int { runs.count }

    /// The most recently pushed run, if any.
    var last: DelimiterRun? { runs.last }

    /// Pushes a delimiter run onto the top of the stack.
    mutating func push(_ run: DelimiterRun) {
        runs.append(run)
    }

    /// Removes every run from the stack.
    mutating func removeAll() {
        runs.removeAll()
    }

    /// Read/write access to a run by index (oldest at `0`).
    subscript(_ index: Int) -> DelimiterRun {
        get { runs[index] }
        set { runs[index] = newValue }
    }

    /// The current run indices, oldest first.
    var indices: Range<Int> { runs.indices }
}
