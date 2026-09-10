/// A stable, content-derived identity for an AST node.
///
/// A `NodeID` is a deterministic 64-bit digest of a node's content (see
/// ``ContentHasher``). Equal nodes produce equal `NodeID`s, and the digest is
/// process-independent (it is *not* derived from `Swift.Hasher`, whose seed is
/// randomized per run), so identity is reproducible across launches and machines.
///
/// It gives the incremental engine a cheap, stable handle: a committed block
/// keeps the same `NodeID` across streamed deltas as long as its content is
/// unchanged, so finished blocks are reused rather than rebuilt. Sibling nodes
/// with identical content share a `NodeID`; the renderer disambiguates such
/// siblings by their position, so equal content never causes an identity clash in
/// layout.
///
/// `NodeID`s are produced by the parser and are not constructed by consumers.
public struct NodeID: Sendable, Hashable {
    /// A deterministic 64-bit content digest of the node.
    public let hash: UInt64

    /// Creates a node identity from a content digest. Internal: identities are
    /// assigned by the parser, never built by API consumers.
    init(hash: UInt64) {
        self.hash = hash
    }
}

/// A small, deterministic FNV-1a hasher used to derive stable ``NodeID`` content
/// digests.
///
/// Unlike `Swift.Hasher`, FNV-1a is seedless and stable across processes, which
/// is exactly what stable-identity rendering needs: two equal nodes built in
/// different runs must hash identically. The hasher distinguishes structurally
/// different nodes by feeding a per-case discriminator before each case's
/// payload, so e.g. `.code("x")` and `.text("x")` never collide.
struct ContentHasher {
    /// 64-bit FNV-1a offset basis.
    private var state: UInt64 = 0xcbf2_9ce4_8422_2325

    /// 64-bit FNV-1a prime.
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    /// Folds a single byte into the running digest.
    mutating func combine(byte: UInt8) {
        state ^= UInt64(byte)
        state = state &* Self.prime
    }

    /// Folds a discriminator value into the digest. Used to tag enum cases and
    /// field boundaries so structurally distinct nodes do not collide.
    mutating func combine(tag: UInt8) {
        combine(byte: tag)
    }

    /// Folds the UTF-8 bytes of a string into the digest, framed by its length
    /// so concatenation ambiguities (`"ab" + "c"` vs `"a" + "bc"`) cannot alias.
    mutating func combine(_ string: String) {
        combine(string.utf8.count)
        for byte in string.utf8 { combine(byte: byte) }
    }

    /// Folds an optional string, distinguishing `nil` from `""`.
    mutating func combine(_ string: String?) {
        if let string {
            combine(tag: 1)
            combine(string)
        } else {
            combine(tag: 0)
        }
    }

    /// Folds a signed integer (little-endian) into the digest.
    mutating func combine(_ value: Int) {
        var bits = UInt64(bitPattern: Int64(value))
        for _ in 0..<8 {
            combine(byte: UInt8(bits & 0xFF))
            bits >>= 8
        }
    }

    /// Folds an optional integer, distinguishing `nil` from `0`.
    mutating func combine(_ value: Int?) {
        if let value {
            combine(tag: 1)
            combine(value)
        } else {
            combine(tag: 0)
        }
    }

    /// Folds an optional boolean, distinguishing `nil`, `false`, and `true`.
    mutating func combine(_ value: Bool?) {
        switch value {
        case .none: combine(tag: 0)
        case .some(false): combine(tag: 1)
        case .some(true): combine(tag: 2)
        }
    }

    /// Folds a boolean into the digest.
    mutating func combine(_ value: Bool) {
        combine(tag: value ? 1 : 0)
    }

    /// The finalized 64-bit digest.
    var value: UInt64 { state }
}
