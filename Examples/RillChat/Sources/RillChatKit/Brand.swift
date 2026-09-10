import SwiftUI

/// A small, explicit palette so the chat renders identically regardless of the
/// system appearance (semantic colors like `.primary` would flip with dark mode).
public struct Palette: Sendable {
    public var bg, surface, userSurface, border, ink, ink2, accent, codeBG: Color
    public var scheme: ColorScheme
}

@inline(__always) func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

public extension Palette {
    /// Deep, cool dark — the app's primary look.
    static let dark = Palette(
        bg: c(0.039, 0.055, 0.078), surface: c(0.078, 0.098, 0.129), userSurface: c(0.12, 0.16, 0.22),
        border: c(0.13, 0.16, 0.21), ink: c(0.905, 0.925, 0.955), ink2: c(0.52, 0.57, 0.65),
        accent: c(0.36, 0.62, 0.98), codeBG: c(0.055, 0.072, 0.10), scheme: .dark)

    /// A restrained light theme — same app, different `RillTheme`.
    static let light = Palette(
        bg: c(0.965, 0.975, 0.985), surface: .white, userSurface: c(0.93, 0.95, 0.99),
        border: c(0.90, 0.92, 0.95), ink: c(0.09, 0.11, 0.16), ink2: c(0.42, 0.46, 0.53),
        accent: c(0.13, 0.42, 0.94), codeBG: c(0.965, 0.975, 0.985), scheme: .light)
}
