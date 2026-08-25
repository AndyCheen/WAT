// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Core",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
            ]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"])
    ]
)
