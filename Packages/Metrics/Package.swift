// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Metrics",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Metrics", targets: ["Metrics"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
    ],
    targets: [
        .target(
            name: "Metrics",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
            ]
        ),
        .testTarget(name: "MetricsTests", dependencies: ["Metrics"])
    ]
)
