import XCTest
import RillCore
import RillAnalytics
import RillUI
@testable import RillDemoKit

/// Headless tests for the RillDemo sample. These never touch pixels: they assert
/// on the streaming simulator's chunking, on parsed document/view-model state,
/// and on the analytics HUD's captured metrics.
final class RillDemoTests: XCTestCase {

    // MARK: - StreamingSimulator chunking

    func testSimulatorChunksReassembleToOriginal() {
        let text = "# Title\n\nSome **bold** text with a `code` span and more words to chunk."
        let simulator = StreamingSimulator(text: text, chunkSize: 5, delay: .milliseconds(1))
        let chunks = simulator.chunks()

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.joined(), text)
    }

    func testSimulatorRespectsChunkSizeInCharacters() {
        let text = String(repeating: "a", count: 23)
        let simulator = StreamingSimulator(text: text, chunkSize: 5, delay: .zero)
        let chunks = simulator.chunks()

        // 23 / 5 = 5 chunks (four of 5, one of 3).
        XCTAssertEqual(chunks.count, 5)
        XCTAssertEqual(chunks.dropLast().allSatisfy { $0.count == 5 }, true)
        XCTAssertEqual(chunks.last?.count, 3)
    }

    func testSimulatorClampsChunkSizeToAtLeastOne() {
        let text = "abc"
        let simulator = StreamingSimulator(text: text, chunkSize: 0, delay: .zero)
        let chunks = simulator.chunks()
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertEqual(chunks.allSatisfy { !$0.isEmpty }, true)
    }

    // MARK: - Streaming equivalence (demonstrated by the demo)

    @MainActor
    func testStreamedSourceMatchesOneShotParse() {
        let text = ShowcaseDocument.markdown
        let simulator = StreamingSimulator(text: text, chunkSize: 7, delay: .zero)

        let source = MarkdownSource()
        for chunk in simulator.chunks() {
            source.append(chunk)
        }

        let oneShot = MarkdownView.parse(text)
        XCTAssertEqual(source.document, oneShot)
    }

    // MARK: - HUD analytics sink

    @MainActor
    func testHUDSinkCapturesParseAndRenderMetrics() {
        let hud = HUDAnalyticsSink()
        let source = MarkdownSource(analytics: hud)

        let simulator = StreamingSimulator(
            text: ShowcaseDocument.markdown,
            chunkSize: 8,
            delay: .zero
        )
        for chunk in simulator.chunks() {
            source.append(chunk)
        }

        // Parse metrics were observed.
        XCTAssertGreaterThan(hud.snapshot.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(hud.snapshot.dirtyTailBytes, 0)
        // Streaming reuses committed blocks as the document grows.
        XCTAssertGreaterThan(hud.snapshot.blocksReused, 0)
        // Parse time is reported in milliseconds (non-negative).
        XCTAssertGreaterThanOrEqual(hud.snapshot.parseMilliseconds, 0)
    }

    @MainActor
    func testHUDSinkResetClearsSnapshot() {
        let hud = HUDAnalyticsSink()
        hud.didParse(ParseMetrics(
            duration: .milliseconds(2),
            dirtyTailBytes: 10,
            totalBytes: 100,
            blocksCommitted: 1,
            blocksReused: 3
        ))
        XCTAssertEqual(hud.snapshot.totalBytes, 100)

        hud.reset()
        XCTAssertEqual(hud.snapshot.totalBytes, 0)
        XCTAssertEqual(hud.snapshot.blocksReused, 0)
    }

    // MARK: - Theme catalog (switcher)

    func testThemeCatalogProvidesMultipleNamedThemes() {
        let catalog = ThemeCatalog.all
        XCTAssertGreaterThanOrEqual(catalog.count, 2)
        // Names are unique and non-empty.
        let names = catalog.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Showcase document content

    func testShowcaseDocumentExercisesEveryFeature() {
        let document = MarkdownView.parse(ShowcaseDocument.markdown)
        let blocks = document.blocks

        XCTAssertTrue(blocks.contains { if case .heading = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .list = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .table = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .codeBlock = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .mathBlock = $0 { return true } else { return false } })

        // A citation appears somewhere in the inline content.
        XCTAssertTrue(documentContainsCitation(document))
    }

    private func documentContainsCitation(_ document: Document) -> Bool {
        func inlinesHaveCitation(_ inlines: [Inline]) -> Bool {
            for inline in inlines {
                switch inline {
                case .citation:
                    return true
                case let .emphasis(children),
                     let .strong(children),
                     let .strikethrough(children):
                    if inlinesHaveCitation(children) { return true }
                case let .link(link):
                    if inlinesHaveCitation(link.inlines) { return true }
                default:
                    continue
                }
            }
            return false
        }

        func blocksHaveCitation(_ blocks: [Block]) -> Bool {
            for block in blocks {
                switch block {
                case let .paragraph(paragraph):
                    if inlinesHaveCitation(paragraph.inlines) { return true }
                case let .heading(heading):
                    if inlinesHaveCitation(heading.inlines) { return true }
                case let .blockQuote(quote):
                    if blocksHaveCitation(quote.blocks) { return true }
                case let .list(list):
                    for item in list.items where blocksHaveCitation(item.blocks) {
                        return true
                    }
                default:
                    continue
                }
            }
            return false
        }

        return blocksHaveCitation(document.blocks)
    }
}
