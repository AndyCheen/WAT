// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Insights",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Insights", targets: ["Insights"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
        .package(path: "../Metrics"),
    ],
    targets: [
        .target(
            name: "Insights",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Metrics", package: "Metrics"),
            ]
        ),
        .testTarget(name: "InsightsTests", dependencies: ["Insights"])
    ]
)
