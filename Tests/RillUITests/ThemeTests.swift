import XCTest
import SwiftUI
@testable import RillUI

/// Tests for ``RillTheme`` and ``RenderConfig``.
///
/// These assert the zero-configuration contract: every slot of the default
/// theme is fully populated (no `nil` fonts/colors/metrics) so the package
/// looks good with no configuration, and ``RenderConfig`` exposes sensible
/// defaults. Tests run headlessly: they inspect theme/config values, never
/// rendered pixels.
@MainActor
final class ThemeTests: XCTestCase {

    // MARK: - Default theme is fully populated

    func testDefaultThemeHeadingFontsCoverLevelsOneThroughSix() {
        let fonts = RillTheme.default.fonts
        for level in 1...6 {
            // Must not trap and must return a usable font for every level.
            _ = fonts.heading(level: level)
        }
    }

    func testDefaultThemeFontsAllSlotsPresent() {
        let fonts = RillTheme.default.fonts
        // All stored font slots exist by construction; reading them must not
        // trap and each heading slot is individually addressable.
        _ = fonts.body
        _ = fonts.heading1
        _ = fonts.heading2
        _ = fonts.heading3
        _ = fonts.heading4
        _ = fonts.heading5
        _ = fonts.heading6
        _ = fonts.code
        _ = fonts.blockquote
        _ = fonts.table
    }

    func testHeadingLookupClampsOutOfRange() {
        let fonts = RillTheme.default.fonts
        // Out-of-range levels clamp to the nearest valid heading rather than
        // trapping, so a malformed AST never crashes rendering.
        XCTAssertEqual(fonts.heading(level: 0), fonts.heading1)
        XCTAssertEqual(fonts.heading(level: 7), fonts.heading6)
        XCTAssertEqual(fonts.heading(level: -5), fonts.heading1)
        XCTAssertEqual(fonts.heading(level: 3), fonts.heading3)
    }

    func testDefaultThemeColorsAllSlotsPresent() {
        let colors = RillTheme.default.colors
        _ = colors.textPrimary
        _ = colors.textSecondary
        _ = colors.link
        _ = colors.codeBackground
        _ = colors.quoteBar
        _ = colors.citation
        _ = colors.tableBorder
    }

    func testDefaultThemeMetricsArePositive() {
        let metrics = RillTheme.default.metrics
        XCTAssertGreaterThan(metrics.paragraphSpacing, 0)
        XCTAssertGreaterThan(metrics.listIndent, 0)
        XCTAssertGreaterThanOrEqual(metrics.blockPadding, 0)
        XCTAssertGreaterThanOrEqual(metrics.codePadding, 0)
        XCTAssertGreaterThanOrEqual(metrics.cornerRadius, 0)
        XCTAssertGreaterThanOrEqual(metrics.codeCornerRadius, 0)
    }

    func testDefaultThemeCodeBlockStyleIsConfigured() {
        // The default code block style must be a fully-specified case with a
        // sane preview line count.
        switch RillTheme.default.codeBlock {
        case let .inlineScrollable(maxPreviewLines),
             let .tappableCard(maxPreviewLines):
            XCTAssertGreaterThan(maxPreviewLines, 0)
        }
    }

    func testDefaultThemeIsSendableValueType() {
        // Copying must not share reference state: mutating a copy leaves the
        // original default untouched.
        var copy = RillTheme.default
        copy.metrics.paragraphSpacing += 100
        XCTAssertNotEqual(copy.metrics.paragraphSpacing,
                          RillTheme.default.metrics.paragraphSpacing)
    }

    // MARK: - CodeBlockStyle

    func testCodeBlockStyleMaxPreviewLinesAccessor() {
        XCTAssertEqual(CodeBlockStyle.inlineScrollable(maxPreviewLines: 12).maxPreviewLines, 12)
        XCTAssertEqual(CodeBlockStyle.tappableCard(maxPreviewLines: 5).maxPreviewLines, 5)
    }

    // MARK: - CitationTarget

    func testCitationTargetStoresTitleAndURL() {
        let target = CitationTarget(title: "Spec", url: "https://example.com")
        XCTAssertEqual(target.title, "Spec")
        XCTAssertEqual(target.url, "https://example.com")

        let untitledLink = CitationTarget(title: "Note", url: nil)
        XCTAssertNil(untitledLink.url)
    }

    // MARK: - RenderConfig defaults

    func testRenderConfigDefaultsArePresent() {
        let config = RenderConfig.default
        // Sensible defaults: appearance animates, and the optional hooks are
        // absent until the host injects them.
        XCTAssertTrue(config.animatesAppearance)
        XCTAssertNil(config.citationResolver)
        XCTAssertNil(config.linkHandler)
        XCTAssertNil(config.imageLoader)
    }

    func testRenderConfigCitationResolverIsInvokable() {
        let config = RenderConfig(
            animatesAppearance: false,
            citationResolver: { marker in
                CitationTarget(title: "Ref \(marker)", url: "https://r/\(marker)")
            }
        )
        XCTAssertFalse(config.animatesAppearance)
        let resolved = config.citationResolver?("7")
        XCTAssertEqual(resolved?.title, "Ref 7")
        XCTAssertEqual(resolved?.url, "https://r/7")
    }

    func testRenderConfigLinkHandlerIsInvokable() {
        let captured = LinkCapture()
        let config = RenderConfig(linkHandler: { url in captured.value = url })
        config.linkHandler?(URL(string: "https://example.com")!)
        XCTAssertEqual(captured.value?.absoluteString, "https://example.com")
    }

    func testImageLoadingProtocolConformerLoadsImage() async {
        let loader: ImageLoading = StubImageLoader()
        let image = try? await loader.image(for: URL(string: "https://img/1.png")!)
        XCTAssertNotNil(image)
    }
}

// MARK: - Test doubles

/// Reference box so the escaping `linkHandler` can publish a captured URL out
/// of its closure for assertion.
private final class LinkCapture: @unchecked Sendable {
    var value: URL?
}

/// Minimal ``ImageLoading`` conformer proving the protocol's async signature is
/// usable from a `Sendable` value without importing UIKit.
private struct StubImageLoader: ImageLoading {
    func image(for url: URL) async throws -> Image {
        Image(systemName: "photo")
    }
}
