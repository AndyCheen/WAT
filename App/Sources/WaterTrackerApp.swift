import SwiftUI
import UIKit
import Core
import Persistence
import Features
import Notifications

@main
struct WaterTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let services = AppContainer.services

    var body: some Scene {
        WindowGroup {
            RootView(services: services, initialRoute: AppContainer.launch.startRoute)
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
            switch phase {
            case .active: services.handleBecameActive()
            case .background: enterBackground()
            default: break
            }
        }
    }

    /// План має бути актуальним до того, як iOS призупинить застосунок: відкладене
    /// перепланування після останньої порції інакше не встигло б (§16.3).
    private func enterBackground() {
        let application = UIApplication.shared
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = application.beginBackgroundTask {
            application.endBackgroundTask(taskId)
        }
        Task { @MainActor in
            await services.handleEnteredBackground()
            AppDelegate.scheduleBackgroundRefresh()
            application.endBackgroundTask(taskId)
        }
    }
}

/// Прапорці запуску — потрібні e2e-тестам, щоб стартувати з чистої або демо-бази.
struct LaunchConfiguration {
    let isInMemory: Bool
    let seedsDemoData: Bool
    /// `--start-screen progress|achievements|prizes|stats|notifications|notification-plan` —
    /// відкрити екран одразу. Використовується для дизайн-QA та e2e без ручної навігації.
    let startRoute: AppRoute?
    /// `--uitest-empty` / `--uitest-demo`: in-memory база й центр сповіщень у пам'яті.
    let isUITest: Bool
    /// `--notifications-auth authorized|denied|notDetermined` — дозвіл фейкового центру (типово є:
    /// шторка дозволу після першої порції інакше ламала б сценарії з кількома тапами).
    let notificationAuthorization: NotificationAuthorization
    /// `--uitest-now 2026-10-01T07:00:00+03:00` — фіксований годинник, щоб план сповіщень
    /// у DEBUG-екрані був детермінованим.
    let fixedNow: Date?
    /// `--notification-tap reminder|morning|evening|rescue|comeback|echo` — імітація тапу
    /// по сповіщенню: реальні сповіщення в симуляторі нестабільні (SPEC-NOTIFICATIONS §16.11).
    let notificationTap: NotificationType?

    static var current: LaunchConfiguration {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let isUITest = arguments.contains("--uitest-empty") || arguments.contains("--uitest-demo")

        let route: AppRoute?
        switch value(after: "--start-screen") {
        case "progress": route = .progress
        case "achievements": route = .achievements
        case "prizes": route = .prizes
        case "stats": route = .stats
        case "notifications": route = .notifications
        case "notification-plan": route = .notificationPlan
        default: route = nil
        }

        let authorization: NotificationAuthorization
        switch value(after: "--notifications-auth") {
        case "denied": authorization = .denied
        case "notDetermined": authorization = .notDetermined
        default: authorization = .authorized
        }

        return LaunchConfiguration(
            isInMemory: isUITest,
            seedsDemoData: arguments.contains("--uitest-demo") || arguments.contains("--seed-demo"),
            startRoute: route,
            isUITest: isUITest,
            notificationAuthorization: authorization,
            fixedNow: value(after: "--uitest-now").flatMap { ISO8601DateFormatter().date(from: $0) },
            notificationTap: value(after: "--notification-tap").flatMap(NotificationType.init(key:))
        )
    }
}
