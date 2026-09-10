import Foundation

/// A small, lexical description of one programming language, sufficient for the
/// fast token classes (``SyntaxTokenKind``) RillUI colors.
///
/// `Grammar` is purely declarative data — keyword sets and delimiter strings —
/// consumed by ``SyntaxTokenizer``. It models only what the coarse highlighter
/// needs: where comments and string/character literals begin and end, which
/// identifiers are reserved words, and (for markup) whether tag names should be
/// treated as keywords. Anything not matched falls through to ``/plain``.
///
/// Grammars are resolved by tag via ``Grammar/forLanguage(_:)``; an unknown or
/// `nil` tag yields ``Grammar/generic``.
struct Grammar: Sendable {
    /// A paired comment delimiter, e.g. `/*` … `*/`. A `nil` `close` marks a
    /// line comment that runs to the end of the line.
    struct CommentSyntax: Sendable {
        /// The opening marker (e.g. `//`, `/*`, `#`, `<!--`).
        var open: String
        /// The closing marker for block comments, or `nil` for line comments.
        var close: String?
    }

    /// A string/character literal delimiter pair.
    struct StringSyntax: Sendable {
        /// The opening delimiter (e.g. `"`, `'`, `` ` ``).
        var open: Character
        /// The closing delimiter (usually equal to ``open``).
        var close: Character
        /// Whether a backslash escapes the next character inside the literal.
        var allowsEscapes: Bool

        init(open: Character, close: Character? = nil, allowsEscapes: Bool = true) {
            self.open = open
            self.close = close ?? open
            self.allowsEscapes = allowsEscapes
        }
    }

    /// The reserved words to color as ``SyntaxTokenKind/keyword``.
    var keywords: Set<String>
    /// The comment forms recognized, longest-opener-first at match time.
    var comments: [CommentSyntax]
    /// The string/character literal delimiters recognized.
    var strings: [StringSyntax]
    /// Whether this grammar is markup (HTML): tag names become keywords and
    /// `<!-- -->` is the comment form.
    var isMarkup: Bool

    init(
        keywords: Set<String>,
        comments: [CommentSyntax],
        strings: [StringSyntax],
        isMarkup: Bool = false
    ) {
        self.keywords = keywords
        self.comments = comments
        self.strings = strings
        self.isMarkup = isMarkup
    }
}

extension Grammar {

    /// Resolves a fenced-code language tag to a grammar.
    ///
    /// Matching is case-insensitive and tolerant of the common aliases models
    /// emit (`js`/`javascript`, `ts`/`typescript`, `py`/`python`, `sh`/`bash`,
    /// `rs`/`rust`, …). An unrecognized or `nil` tag returns ``generic``.
    ///
    /// - Parameter language: The language tag, or `nil`.
    /// - Returns: The matching grammar, or ``generic`` when unknown.
    static func forLanguage(_ language: String?) -> Grammar {
        guard let raw = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .generic
        }
        switch raw.lowercased() {
        case "swift":
            return .swift
        case "js", "javascript", "jsx", "node":
            return .javaScript
        case "ts", "typescript", "tsx":
            return .typeScript
        case "py", "python", "python3":
            return .python
        case "json", "json5", "jsonc":
            return .json
        case "bash", "sh", "shell", "zsh", "shellscript":
            return .bash
        case "html", "htm", "xml", "xhtml", "svg":
            return .html
        case "rust", "rs":
            return .rust
        default:
            return .generic
        }
    }

    // MARK: - Shared delimiter sets

    /// `//` line + `/* */` block comments, used by C-family languages.
    private static let cFamilyComments: [CommentSyntax] = [
        CommentSyntax(open: "/*", close: "*/"),
        CommentSyntax(open: "//", close: nil),
    ]

    /// `#` line comments, used by shell/Python-family languages.
    private static let hashComments: [CommentSyntax] = [
        CommentSyntax(open: "#", close: nil),
    ]

    /// Double-quoted strings only.
    private static let doubleQuote: [StringSyntax] = [
        StringSyntax(open: "\""),
    ]

    /// Single- and double-quoted strings (plus backtick for JS templates).
    private static let jsStrings: [StringSyntax] = [
        StringSyntax(open: "\""),
        StringSyntax(open: "'"),
        StringSyntax(open: "`"),
    ]

    // MARK: - Language grammars

    /// The language-agnostic fallback: `//`/`#` comments, single/double-quoted
    /// strings, numbers — but no keyword set, so identifiers stay ``plain``.
    static let generic = Grammar(
        keywords: [],
        comments: [
            CommentSyntax(open: "/*", close: "*/"),
            CommentSyntax(open: "//", close: nil),
            CommentSyntax(open: "#", close: nil),
        ],
        strings: [
            StringSyntax(open: "\""),
            StringSyntax(open: "'"),
        ]
    )

    static let swift = Grammar(
        keywords: [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
            "func", "import", "init", "inout", "internal", "let", "open", "operator",
            "private", "precedencegroup", "protocol", "public", "rethrows", "static",
            "struct", "subscript", "typealias", "var", "actor", "async", "await",
            "break", "case", "continue", "default", "defer", "do", "else",
            "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw",
            "switch", "where", "while", "as", "catch", "is", "nil", "super", "self",
            "Self", "throws", "true", "false", "try", "some", "any", "Any", "weak",
            "unowned", "lazy", "final", "mutating", "nonmutating", "convenience",
            "required", "override", "indirect", "dynamic", "optional", "willSet",
            "didSet", "get", "set",
        ],
        comments: cFamilyComments,
        strings: doubleQuote
    )

    static let javaScript = Grammar(
        keywords: [
            "var", "let", "const", "function", "return", "if", "else", "for",
            "while", "do", "switch", "case", "default", "break", "continue",
            "new", "delete", "typeof", "instanceof", "in", "of", "this", "super",
            "class", "extends", "import", "export", "from", "as", "default",
            "async", "await", "yield", "try", "catch", "finally", "throw",
            "void", "null", "undefined", "true", "false", "static", "get", "set",
        ],
        comments: cFamilyComments,
        strings: jsStrings
    )

    static let typeScript = Grammar(
        keywords: javaScript.keywords.union([
            "interface", "type", "enum", "namespace", "declare", "abstract",
            "implements", "public", "private", "protected", "readonly", "keyof",
            "infer", "is", "asserts", "satisfies", "unknown", "never", "any",
            "string", "number", "boolean", "object", "symbol",
        ]),
        comments: cFamilyComments,
        strings: jsStrings
    )

    static let python = Grammar(
        keywords: [
            "False", "None", "True", "and", "as", "assert", "async", "await",
            "break", "class", "continue", "def", "del", "elif", "else", "except",
            "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try",
            "while", "with", "yield", "match", "case", "self", "cls",
        ],
        comments: hashComments,
        strings: [
            StringSyntax(open: "\""),
            StringSyntax(open: "'"),
        ]
    )

    static let json = Grammar(
        keywords: ["true", "false", "null"],
        comments: [],
        strings: doubleQuote
    )

    static let bash = Grammar(
        keywords: [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "while",
            "until", "do", "done", "in", "function", "select", "time", "return",
            "exit", "break", "continue", "local", "export", "readonly", "declare",
            "echo", "cd", "set", "unset", "source", "alias", "trap", "test",
        ],
        comments: hashComments,
        strings: [
            StringSyntax(open: "\""),
            StringSyntax(open: "'", allowsEscapes: false),
        ]
    )

    static let html = Grammar(
        keywords: [],
        comments: [
            CommentSyntax(open: "<!--", close: "-->"),
        ],
        strings: doubleQuote,
        isMarkup: true
    )

    static let rust = Grammar(
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn",
            "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in",
            "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
            "self", "Self", "static", "struct", "super", "trait", "true", "type",
            "unsafe", "use", "where", "while", "union", "box", "macro_rules",
        ],
        comments: cFamilyComments,
        strings: doubleQuote
    )
}
