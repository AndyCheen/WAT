import Foundation
import SwiftData
import Core
import Persistence
import Gamification
import Features
import Notifications

/// Єдиний екземпляр сервісів застосунку.
///
/// Лінивий `static`, а не `@State` у `App`: делегат `UNUserNotificationCenter` має бути
/// виставлений до кінця запуску, і дія, що запустила застосунок із закритого стану, приходить
/// у делегат раніше, ніж SwiftUI збудує перше вікно (SPEC-NOTIFICATIONS §16.4).
@MainActor
enum AppContainer {
    static let launch = LaunchConfiguration.current

    static let services: AppServices = {
        let container: ModelContainer
        do {
            container = try Database.makeContainer(inMemory: launch.isInMemory)
        } catch {
            container = Database.makeInMemoryContainer()
        }
        let clock: Clock = launch.fixedNow.map { FixedClock(now: $0) } ?? SystemClock()
        // e2e не бачать системних запитів: центр у пам'яті з дозволом, заданим прапорцем.
        let center: NotificationCenterProtocol = launch.isUITest
            ? InMemoryNotificationCenter(status: launch.notificationAuthorization)
            : SystemNotificationCenter()
        let services = AppServices(
            container: container, clock: clock, notificationCenter: center,
            bubbleSoundAvailable: Bundle.main.url(forResource: "drop", withExtension: "caf") != nil,
            xpRules: xpRules
        )
        services.bootstrap()
        if launch.seedsDemoData {
            FixtureSeeder.seed(into: services)
        }
        if launch.seedsScheduleShift {
            FixtureSeeder.seedScheduleShift(into: services)
        }
        if let demo = launch.scheduleSuggestion {
            services.showScheduleSuggestion(demo)
        }
        if let tap = launch.notificationTap {
            services.simulateNotificationTap(tap)
        }
        return services
    }()

    /// Баланс XP: `Config/Balance.xcconfig` → `Info.plist`, а в DEBUG — ще й змінні середовища схеми,
    /// щоб пробувати числа без правки конфігурації (SPEC-PRIZES §16.13).
    static var xpRules: XPRules {
        var values: [String: String] = [:]
        for key in XPRules.BalanceKey.all {
            if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String { values[key] = value }
            #if DEBUG
            if let value = ProcessInfo.processInfo.environment[key] { values[key] = value }
            #endif
        }
        return XPRules.default.applyingBalance(values)
    }
}
