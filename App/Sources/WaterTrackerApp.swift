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
    /// `--start-screen progress|level-road|achievements|prizes|stats|settings|notifications|notification-plan|report|schedule-suggestion` —
    /// відкрити екран одразу. Використовується для дизайн-QA та e2e без ручної навігації.
    /// `report` — звіт за минулий тиждень; конкретний період — `report:day:2026-10-04`,
    /// `report:month:2026-09` (кілька — через кому, як у злитому сповіщенні).
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
    /// `--start-screen schedule-suggestion[:wake-early|wake-late|sleep-late|sleep-early|both|weekend|weekdays]` —
    /// вікно «Графік дня» одразу, повз правило частоти (WAT-41). Без варіанта — ранній підйом.
    let scheduleSuggestion: ScheduleSuggestionDemo?
    /// `--seed-schedule-shift` — 10 днів із першою склянкою ≈ 06:30: вікно з'являється саме, як у житті.
    let seedsScheduleShift: Bool

    static var current: LaunchConfiguration {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let isUITest = arguments.contains("--uitest-empty") || arguments.contains("--uitest-demo")

        let route: AppRoute?
        var scheduleSuggestion: ScheduleSuggestionDemo?
        switch value(after: "--start-screen") {
        case "progress": route = .progress
        case "level-road": route = .levelRoad
        case "achievements": route = .achievements
        case "prizes": route = .prizes
        case "stats": route = .stats
        case "settings": route = .settings
        case "notifications": route = .notifications
        case "notification-plan": route = .notificationPlan
        case let screen? where screen.hasPrefix("report"):
            let periods = screen.dropFirst("report".count).drop { $0 == ":" }
                .split(separator: ",").compactMap { ReportPeriod(encoded: String($0)) }
            route = .report(periods)
        case let screen? where screen.hasPrefix("schedule-suggestion"):
            let variant = screen.dropFirst("schedule-suggestion".count).drop { $0 == ":" }
            scheduleSuggestion = ScheduleSuggestionDemo(rawValue: String(variant)) ?? .wakeEarly
            route = nil
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
            notificationTap: value(after: "--notification-tap").flatMap(NotificationType.init(key:)),
            scheduleSuggestion: scheduleSuggestion,
            seedsScheduleShift: arguments.contains("--seed-schedule-shift")
        )
    }
}
