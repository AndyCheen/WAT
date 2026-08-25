// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Persistence",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "Core", package: "Core"),
            ]
        ),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"])
    ]
)
