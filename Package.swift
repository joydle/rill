// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Rill",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "RillCore", targets: ["RillCore"]),
        .library(name: "RillMath", targets: ["RillMath"]),
        .library(name: "RillAnalytics", targets: ["RillAnalytics"]),
        .library(name: "RillUI", targets: ["RillUI"]),
    ],
    targets: [
        // MARK: Library targets

        .target(
            name: "RillCore",
            dependencies: ["RillAnalytics"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RillMath",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RillAnalytics",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RillUI",
            dependencies: ["RillCore", "RillMath", "RillAnalytics"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: Test targets

        .testTarget(
            name: "RillCoreTests",
            dependencies: ["RillCore", "RillAnalytics"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RillMathTests",
            dependencies: ["RillMath"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RillAnalyticsTests",
            dependencies: ["RillAnalytics"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RillUITests",
            dependencies: ["RillUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
