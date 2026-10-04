import SwiftUI
import SwiftData
import Core
import Persistence
import Features

@main
struct WaterTrackerApp: App {
    @State private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let launch = LaunchConfiguration.current
        let container: ModelContainer
        do {
            container = try Database.makeContainer(inMemory: launch.isInMemory)
        } catch {
            container = Database.makeInMemoryContainer()
        }

        let services = AppServices(container: container, clock: SystemClock())
        services.bootstrap()
        if launch.seedsDemoData {
            FixtureSeeder.seed(into: services)
        }
        _services = State(initialValue: services)
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services, initialRoute: LaunchConfiguration.current.startRoute)
                // Північ і переведення годинника, поки застосунок на екрані.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    NSTimeZone.resetSystemTimeZone()
                    services.handleTimeChange()
                }
                // Системний пояс кешується процесом — без скидання `TimeZone.current`
                // віддавав би старий пояс до перезапуску (SPEC-NOTIFICATIONS §16.6).
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    NSTimeZone.resetSystemTimeZone()
                    services.handleTimeChange()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { services.handleBecameActive() }
        }
    }
}

/// Прапорці запуску — потрібні e2e-тестам, щоб стартувати з чистої або демо-бази.
struct LaunchConfiguration {
    let isInMemory: Bool
    let seedsDemoData: Bool
    /// `--start-screen progress|achievements|prizes|stats` — відкрити екран одразу.
    /// Використовується для дизайн-QA та e2e без ручної навігації.
    let startRoute: AppRoute?

    static var current: LaunchConfiguration {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("--uitest-empty") || arguments.contains("--uitest-demo")

        var route: AppRoute?
        if let index = arguments.firstIndex(of: "--start-screen"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "progress": route = .progress
            case "achievements": route = .achievements
            case "prizes": route = .prizes
            case "stats": route = .stats
            default: route = nil
            }
        }

        return LaunchConfiguration(
            isInMemory: isUITest,
            seedsDemoData: arguments.contains("--uitest-demo") || arguments.contains("--seed-demo"),
            startRoute: route
        )
    }
}
