/// A sink that accepts progressively-arriving Markdown text.
///
/// Streaming sources (an LLM token stream, an SSE delta feed) feed an
/// incremental parser through one of two entry points:
///
/// - ``consume(snapshot:)`` delivers the *entire* text seen so far on each call.
///   The parser diffs it against its buffer and re-lexes only what changed.
/// - ``consume(delta:at:)`` delivers an append-delta: `offset` is the byte index
///   the new text begins at, so the parser truncates its buffer to `offset` and
///   appends. Re-emitting an overlapping range is idempotent.
///
/// Both forms normalize into one growing UTF-8 buffer, so a producer may freely
/// mix them. Conformers are reference types (a parser holds mutable buffer state)
/// and are not safe to share across threads without external isolation.
public protocol MarkdownStreamConsumer: AnyObject {
    /// Consumes the full text accumulated so far, replacing prior input.
    /// - Parameter snapshot: The complete Markdown text seen up to this point.
    func consume(snapshot: String)

    /// Consumes an append-delta at a byte offset.
    /// - Parameters:
    ///   - delta: The newly-arrived Markdown text.
    ///   - offset: The UTF-8 byte index in the accumulated buffer where `delta`
    ///     begins. The buffer is truncated to `offset` before `delta` is appended,
    ///     which makes overlapping re-emits idempotent.
    func consume(delta: String, at offset: Int)
}
