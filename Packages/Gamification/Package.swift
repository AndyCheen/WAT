// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Gamification",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Gamification", targets: ["Gamification"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
        .package(path: "../Metrics"),
    ],
    targets: [
        .target(
            name: "Gamification",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Metrics", package: "Metrics"),
            ]
        ),
        .testTarget(name: "GamificationTests", dependencies: ["Gamification"])
    ]
)
