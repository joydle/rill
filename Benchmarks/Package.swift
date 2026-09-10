// swift-tools-version:6.0
import PackageDescription

// Benchmarks is a SEPARATE SwiftPM package that lives inside the Rill repo but is
// NOT part of the main Rill package graph. It is the ONLY place external
// dependencies are allowed — the main Rill package stays zero-dependency.
//
// Strategies A (Rill incremental) and B (Rill full-reparse) use ONLY the local
// Rill package and therefore ALWAYS build and run offline, with no external deps.
//
// The competitor strategies are each gated by a compile-time define and an
// `enable*` flag below. When a flag is on, the matching dependency is added and
// the define is passed to the compiler; the corresponding strategy is compiled
// behind `#if <DEFINE>`. When a dependency cannot be fetched (offline) or fails to
// build, flip its flag to `false`: the benchmark still compiles and runs with
// whatever strategies remain available (A and B at minimum). There are NO SwiftPM
// package traits declared — gating is purely these flags + `#if` defines.
//
//   Flag                 Define              Strategy / dependency
//   ----                 ------              ---------------------
//   enableSwiftMarkdown  HAVE_SWIFT_MARKDOWN C — swift-markdown 0.7.3 (cmark-gfm);
//                                              Microsoft SSM's actual parsing core.
//   enableMarkdownUI     HAVE_MARKDOWN_UI    E — MarkdownUI 2.4.1 (its own swift-cmark
//                                              0.8.0); most popular SwiftUI md renderer.
//   enableMicrosoft      HAVE_MS_SSM         D — microsoft/SwiftStreamingMarkdown
//                                              (their real MarkdownParserImpl, revision
//                                              947e958), timed through its async parse.
//
// Strategy F (Apple `AttributedString(markdown:)`) needs NO dependency — it only
// imports Foundation and is always available.

// Flip any flag to `false` to drop that dependency. Setting all three to `false`
// guarantees a fully offline, zero-external-dependency build of the A+B+F benchmark.
let enableSwiftMarkdown = true
let enableMarkdownUI = true
let enableMicrosoft = true

var dependencies: [Package.Dependency] = [
    .package(path: ".."), // local Rill package (one directory up from Benchmarks/)
]
var benchDeps: [Target.Dependency] = [
    .product(name: "RillCore", package: "Rill"),
    .product(name: "RillAnalytics", package: "Rill"),
]
var benchSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

if enableSwiftMarkdown {
    dependencies.append(
        // EXACT 0.7.3 — the same pin used by microsoft/SwiftStreamingMarkdown.
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.7.3")
    )
    benchDeps.append(.product(name: "Markdown", package: "swift-markdown"))
    benchSettings.append(.define("HAVE_SWIFT_MARKDOWN"))
}

if enableMarkdownUI {
    dependencies.append(
        // EXACT 2.4.1 — MarkdownUI, the most popular SwiftUI markdown renderer.
        // Transitively resolves swift-cmark 0.8.0, the SAME version swift-markdown
        // 0.7.3 pulls, so C and E co-resolve cleanly.
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")
    )
    benchDeps.append(.product(name: "MarkdownUI", package: "swift-markdown-ui"))
    benchSettings.append(.define("HAVE_MARKDOWN_UI"))
}

if enableMicrosoft {
    dependencies.append(
        // No release tags exist, so pin by revision for reproducibility.
        .package(
            url: "https://github.com/microsoft/SwiftStreamingMarkdown",
            revision: "947e958edf0d5b4352ac9383ec4de7a9bf8f13b9"
        )
    )
    benchDeps.append(.product(name: "SwiftStreamingMarkdown", package: "SwiftStreamingMarkdown"))
    benchSettings.append(.define("HAVE_MS_SSM"))
}

let package = Package(
    name: "RillBenchmarks",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    dependencies: dependencies,
    targets: [
        .executableTarget(
            name: "RillBench",
            dependencies: benchDeps,
            swiftSettings: benchSettings
        ),
    ]
)
