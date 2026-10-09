import Foundation
import UIKit
import SwiftData
import Core
import Persistence
import Gamification
import Features
import Notifications
import Widgets

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
            xpRules: xpRules,
            // e2e — база в пам'яті: справжній знімок віджетів у App Group вона не переписує.
            widgetStore: launch.isUITest ? WidgetSnapshotStore(url: nil) : .shared,
            widgetReloader: WidgetCenterReloader(),
            widgetPicker: launch.isUITest ? nil : .shared
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
        if let actions = launch.widgetActions {
            Task { await services.simulateWidgetActions(actions) }
        }
        return services
    }()

    /// Дочекатися хвоста дії з віджета (відлуння, перепланування) у фоні. Інтент повертається раніше — заради
    /// швидкої цифри на віджеті (`AppServices.perform`), а після повернення iOS може приспати застосунок:
    /// фонове завдання дає хвосту дійти, інакше нагадування лишилось би за старим планом.
    static func finishInBackground(_ work: Task<Void, Never>) {
        let application = UIApplication.shared
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = application.beginBackgroundTask { application.endBackgroundTask(taskId) }
        Task { @MainActor in
            await work.value
            application.endBackgroundTask(taskId)
        }
    }

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
