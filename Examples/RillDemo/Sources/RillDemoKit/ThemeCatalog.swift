import SwiftUI
import RillUI

/// A named ``RillTheme`` entry shown in the demo's theme switcher.
///
/// Pure value type so the switcher can list and pick themes without touching the
/// renderer. ``id`` is the unique ``name`` so it can drive a SwiftUI `Picker`.
public struct NamedTheme: Identifiable, Sendable {
    /// The human-readable theme name shown in the switcher.
    public let name: String

    /// The theme applied to the rendered showcase document.
    public let theme: RillTheme

    /// Stable identity for SwiftUI; equal to ``name``.
    public var id: String { name }

    /// Creates a named theme.
    /// - Parameters:
    ///   - name: The unique display name.
    ///   - theme: The wrapped ``RillTheme``.
    public init(name: String, theme: RillTheme) {
        self.name = name
        self.theme = theme
    }
}

/// The catalog of themes the demo can switch between at runtime.
///
/// All themes are built by copying ``RillTheme/default`` and overriding a few
/// fields, demonstrating how a host customises Rill without reimplementing the
/// renderer. The demo's theme switcher iterates ``all``.
public enum ThemeCatalog {

    /// Every theme available in the switcher, in display order. The first entry
    /// is the package default.
    public static let all: [NamedTheme] = [
        NamedTheme(name: "Default", theme: .default),
        NamedTheme(name: "Sepia", theme: sepia),
        NamedTheme(name: "Midnight", theme: midnight),
        NamedTheme(name: "High Contrast", theme: highContrast),
    ]

    /// A warm, paper-like reading theme.
    static var sepia: RillTheme {
        var theme = RillTheme.default
        theme.colors.textPrimary = Color(red: 0.30, green: 0.24, blue: 0.16)
        theme.colors.textSecondary = Color(red: 0.45, green: 0.38, blue: 0.28)
        theme.colors.link = Color(red: 0.60, green: 0.33, blue: 0.10)
        theme.colors.citation = Color(red: 0.60, green: 0.33, blue: 0.10)
        theme.colors.codeBackground = Color(red: 0.93, green: 0.88, blue: 0.78)
        theme.colors.quoteBar = Color(red: 0.72, green: 0.55, blue: 0.30)
        theme.metrics.paragraphSpacing = 14
        return theme
    }

    /// A dark, cool theme tuned for low-light reading.
    static var midnight: RillTheme {
        var theme = RillTheme.default
        theme.colors.textPrimary = Color(red: 0.90, green: 0.92, blue: 0.96)
        theme.colors.textSecondary = Color(red: 0.62, green: 0.67, blue: 0.76)
        theme.colors.link = Color(red: 0.45, green: 0.70, blue: 1.00)
        theme.colors.citation = Color(red: 0.55, green: 0.78, blue: 1.00)
        theme.colors.codeBackground = Color(red: 0.12, green: 0.14, blue: 0.20)
        theme.colors.quoteBar = Color(red: 0.35, green: 0.45, blue: 0.65)
        theme.colors.tableBorder = Color(red: 0.30, green: 0.34, blue: 0.42)
        return theme
    }

    /// A maximal-contrast accessibility theme with extra spacing.
    static var highContrast: RillTheme {
        var theme = RillTheme.default
        theme.colors.textPrimary = .black
        theme.colors.textSecondary = Color(white: 0.2)
        theme.colors.link = .blue
        theme.colors.citation = .blue
        theme.colors.codeBackground = Color(white: 0.9)
        theme.colors.quoteBar = .black
        theme.colors.tableBorder = .black
        theme.metrics.paragraphSpacing = 16
        theme.metrics.blockPadding = 14
        return theme
    }
}
