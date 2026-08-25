// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Features",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Features", targets: ["Features"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
        .package(path: "../Metrics"),
        .package(path: "../Hydration"),
        .package(path: "../Gamification"),
        .package(path: "../Insights"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "Features",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Metrics", package: "Metrics"),
                .product(name: "Hydration", package: "Hydration"),
                .product(name: "Gamification", package: "Gamification"),
                .product(name: "Insights", package: "Insights"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"])
    ]
)
