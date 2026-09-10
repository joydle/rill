import Foundation
import SwiftUI

/// The default ``CodeHighlighter``: a small, fast, zero-dependency tokenizer-based
/// highlighter for the languages models emit most.
///
/// `RillSyntax` ships grammars for Swift, JavaScript/TypeScript, Python, JSON,
/// Bash, HTML, and Rust, plus a language-agnostic generic fallback (strings,
/// numbers, `//`/`#` comments). It colors four token classes — keyword, string,
/// comment, number — from the theme's ``RillTheme/SyntaxColors`` palette, leaving
/// everything else in ``RillTheme/SyntaxColors/plain``. Highlighting never alters
/// the source: it only adds the code font and per-run colors.
///
/// ## Threading and caching
/// ``highlight(_:language:)`` is pure given the code and language and is safe to
/// call from any isolation, so RillUI invokes it off the main thread on commit.
/// Results are memoized by code + language behind a lock, so re-highlighting the
/// same growing block during streaming is cheap. Use
/// ``highlightOffMain(_:language:)`` to explicitly hop to a background executor.
///
/// It is a reference type holding the lock-guarded cache; it is otherwise
/// immutable and therefore safe to share (`@unchecked Sendable`, justified by the
/// lock).
public final class RillSyntax: CodeHighlighter, @unchecked Sendable {

    /// The theme whose ``RillTheme/SyntaxColors`` and code font color the output.
    private let theme: RillTheme

    /// The maximum number of cached highlights retained.
    private let cacheLimit: Int

    /// Lock guarding ``cache``, ``insertionOrder``, and the hit counter.
    private let lock = NSLock()

    /// Memoized results keyed by code + language.
    private var cache: [CacheKey: AttributedString] = [:]

    /// FIFO insertion order, used to evict the oldest entry past ``cacheLimit``.
    private var insertionOrder: [CacheKey] = []

    /// The number of cache hits served so far. Exposed for tests and diagnostics.
    private var _cacheHitCount = 0

    /// The number of highlights served from cache rather than recomputed.
    public var cacheHitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _cacheHitCount
    }

    /// Creates a highlighter.
    /// - Parameters:
    ///   - theme: The theme supplying the syntax palette and code font.
    ///   - cacheLimit: The maximum number of memoized highlights (oldest evicted
    ///     first). Defaults to 256.
    public init(theme: RillTheme, cacheLimit: Int = 256) {
        self.theme = theme
        self.cacheLimit = max(1, cacheLimit)
    }

    /// Highlights `code` for `language`, returning an attributed copy whose runs
    /// carry the matching syntax color and the theme's code font.
    ///
    /// The first call for a given code + language tokenizes and memoizes the
    /// result; identical subsequent calls return the cached value and increment
    /// ``cacheHitCount``. Safe to call off the main thread.
    public func highlight(_ code: String, language: String?) -> AttributedString {
        let key = CacheKey(code: code, language: language?.lowercased())

        lock.lock()
        if let cached = cache[key] {
            _cacheHitCount += 1
            lock.unlock()
            return cached
        }
        lock.unlock()

        let built = build(code: code, language: language)

        lock.lock()
        if cache[key] == nil {
            cache[key] = built
            insertionOrder.append(key)
            if insertionOrder.count > cacheLimit {
                let evicted = insertionOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        lock.unlock()

        return built
    }

    /// Highlights `code` on a background executor, suspending the caller until
    /// the (cached or freshly tokenized) result is ready.
    ///
    /// Use this from a `@MainActor` context to keep tokenization off the main
    /// thread during streaming.
    ///
    /// - Parameters:
    ///   - code: The source to highlight.
    ///   - language: The language tag, or `nil` for the generic tokenizer.
    /// - Returns: The highlighted attributed string.
    public func highlightOffMain(_ code: String, language: String?) async -> AttributedString {
        await Task.detached(priority: .userInitiated) { [self] in
            highlight(code, language: language)
        }.value
    }

    // MARK: - Cache key

    /// The memoization key: the verbatim code plus the normalized language tag.
    /// Two highlights collide only when both match, so the same code highlighted
    /// as different languages caches independently.
    private struct CacheKey: Hashable {
        let code: String
        let language: String?
    }

    // MARK: - Building

    /// Tokenizes and colors `code` against the grammar resolved from `language`.
    private func build(code: String, language: String?) -> AttributedString {
        let grammar = Grammar.forLanguage(language)
        let tokenizer = SyntaxTokenizer(grammar: grammar)
        let tokens = tokenizer.tokenize(code)
        let palette = theme.colors.syntax
        let font = theme.fonts.code

        var result = AttributedString()
        for token in tokens {
            var piece = AttributedString(token.text)
            piece.font = font
            piece.foregroundColor = token.kind.color(in: palette)
            result.append(piece)
        }
        return result
    }
}
