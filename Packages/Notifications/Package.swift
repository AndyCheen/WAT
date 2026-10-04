// swift-tools-version: 5.10
import PackageDescription

/// Сповіщення (SPEC-NOTIFICATIONS). На рівні доменних модулів: `Hydration`, `Gamification` й
/// `Insights` не імпортує — усе потрібне приходить простим значенням `NotificationContext`,
/// яке збирає композиційний корінь у `Features` (§16.10).
let package = Package(
    name: "Notifications",
    defaultLocalization: "uk",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Notifications", targets: ["Notifications"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Persistence"),
        .package(path: "../Metrics"),
    ],
    targets: [
        .target(
            name: "Notifications",
            dependencies: [
                .product(name: "Core", package: "Core"),
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Metrics", package: "Metrics"),
            ]
        ),
        .testTarget(name: "NotificationsTests", dependencies: ["Notifications"])
    ]
)
