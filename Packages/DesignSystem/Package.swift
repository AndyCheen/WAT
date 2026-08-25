// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "Core", package: "Core"),
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)
