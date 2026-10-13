// swift-tools-version: 5.10
import PackageDescription

// Віджети (WAT-30, SPEC-WIDGETS): знімок даних, запас води, таймлайн, тексти й в'юшки.
// Доменних модулів не знає, як і `Notifications`: знімок збирає `Features`, а розширення
// віджетів лінкує лише цей пакет — без SwiftData й сервісів.
let package = Package(
    name: "Widgets",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Widgets", targets: ["Widgets"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .target(
            name: "Widgets",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(name: "WidgetsTests", dependencies: ["Widgets"])
    ]
)
