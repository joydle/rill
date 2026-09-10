// swift-tools-version:6.0
import PackageDescription

// RillDemo is a standalone SwiftUI sample app that consumes the local Rill
// package. It depends on Rill via a relative path two directories up
// (Examples/RillDemo -> rill) and has no other dependencies.
//
// `RillDemoKit` holds all the testable logic (streaming simulator, analytics
// HUD sink, showcase document, theme catalog, and the SwiftUI views) so it can
// be exercised headlessly under `swift test`. `RillDemo` is the thin `@main`
// executable that hosts the kit's root view.
let package = Package(
    name: "RillDemo",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    dependencies: [
        .package(name: "Rill", path: "../../"),
    ],
    targets: [
        .target(
            name: "RillDemoKit",
            dependencies: [
                .product(name: "RillUI", package: "Rill"),
                .product(name: "RillCore", package: "Rill"),
                .product(name: "RillAnalytics", package: "Rill"),
                .product(name: "RillMath", package: "Rill"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "RillDemo",
            dependencies: ["RillDemoKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RillDemoTests",
            dependencies: ["RillDemoKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
