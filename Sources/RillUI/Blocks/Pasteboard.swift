import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A minimal cross-platform clipboard shim for the copy actions on code blocks
/// and tables.
///
/// RillUI targets both iOS 18 (`UIPasteboard`) and macOS 15
/// (`NSPasteboard`); this enum hides the platform difference behind a single
/// ``copy(_:)`` entry point. It is a no-op on platforms with neither (so it
/// never fails to compile or traps headlessly).
enum Pasteboard {
    /// Places the given string on the system clipboard.
    /// - Parameter string: The text to copy.
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
