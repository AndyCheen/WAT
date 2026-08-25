// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Hydration",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Hydration", targets: ["Hydration"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
        .package(path: "../Metrics"),
    ],
    targets: [
        .target(
            name: "Hydration",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Metrics", package: "Metrics"),
            ]
        ),
        .testTarget(name: "HydrationTests", dependencies: ["Hydration"])
    ]
)
