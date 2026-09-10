import SwiftUI
import RillCore

/// Renders a thematic break (`---`, `***`, `___`) as a horizontal rule.
struct ThematicBreakView: View {
    /// The visual theme.
    let theme: RillTheme

    var body: some View {
        Divider()
            .overlay(theme.colors.tableBorder)
            .padding(.vertical, theme.metrics.paragraphSpacing / 2)
            .accessibilityHidden(true)
    }
}
