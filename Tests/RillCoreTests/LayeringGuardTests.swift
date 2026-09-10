import XCTest

/// Compiler-independent enforcement of Rill's layering rule: the pure-logic
/// modules (`RillCore`, `RillMath`, `RillAnalytics`) must never depend on a UI
/// framework. This test reads every Swift source file in those modules and
/// asserts none of them import SwiftUI or UIKit. Only `RillUI` is allowed to.
final class LayeringGuardTests: XCTestCase {

    /// Modules that are forbidden from importing any UI framework.
    private static let pureModules = ["RillCore", "RillMath", "RillAnalytics"]

    /// UI-framework module names that must not be imported by the pure modules.
    private static let forbiddenModules = ["SwiftUI", "UIKit"]

    /// Returns the names of UI frameworks imported by a source file, ignoring
    /// any mention inside comments or string literals. Only genuine top-level
    /// `import` statements (optionally attributed, e.g. `@preconcurrency`) count.
    private func forbiddenImports(in source: String) -> [String] {
        var found: [String] = []
        for rawLine in source.split(whereSeparator: \.isNewline) {
            // Drop trailing line comments so prose like "// import SwiftUI" is ignored.
            var line = Substring(rawLine)
            if let commentRange = line.range(of: "//") {
                line = line[line.startIndex..<commentRange.lowerBound]
            }
            // Tokenize on whitespace; an import statement begins with `import`
            // (after an optional attribute such as `@preconcurrency`).
            var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            while let first = tokens.first, first.hasPrefix("@") {
                tokens.removeFirst()
            }
            guard tokens.first == "import", tokens.count >= 2 else { continue }
            // The imported module may be submodule-qualified (e.g. `UIKit.UIView`).
            let module = tokens[1].split(separator: ".").first.map(String.init) ?? tokens[1]
            if Self.forbiddenModules.contains(module) {
                found.append(module)
            }
        }
        return found
    }

    /// Resolves the package root by walking up from this test file's location
    /// until a directory containing `Package.swift` is found. This keeps the
    /// test independent of the working directory `swift test` is invoked from.
    private func packageRoot(file: StaticString = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        let manager = FileManager.default
        for _ in 0..<16 {
            let candidate = dir.appendingPathComponent("Package.swift")
            if manager.fileExists(atPath: candidate.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        throw XCTSkip("Could not locate Package.swift above \(file)")
    }

    /// Recursively collects every `.swift` file under the given directory.
    private func swiftFiles(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    func testPureModulesDoNotImportUIFrameworks() throws {
        let root = try packageRoot()
        let sourcesRoot = root.appendingPathComponent("Sources")

        for module in Self.pureModules {
            let moduleDir = sourcesRoot.appendingPathComponent(module)
            let files = swiftFiles(in: moduleDir)

            XCTAssertFalse(
                files.isEmpty,
                "Expected Swift sources under \(moduleDir.path); found none."
            )

            for file in files {
                let contents = try String(contentsOf: file, encoding: .utf8)
                let violations = forbiddenImports(in: contents)
                XCTAssertTrue(
                    violations.isEmpty,
                    "Layering violation: \(module)/\(file.lastPathComponent) "
                        + "imports \(violations.joined(separator: ", ")). "
                        + "Pure modules must not import UI frameworks."
                )
            }
        }
    }
}
