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
        .package(path: "../Notifications"),
        .package(path: "../DesignSystem"),
        .package(path: "../Widgets"),
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
                .product(name: "Notifications", package: "Notifications"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Widgets", package: "Widgets"),
            ]
        ),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"])
    ]
)
