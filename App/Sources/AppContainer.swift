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

    /// Чому сховище не відкрилося — тоді замість головного `WaterTrackerApp` показує `StoreFailureScreen`.
    /// Раніше помилку тихо підміняла база в пам'яті: людина бачила онбординг і порожню історію, а записане до
    /// перезапуску зникало (WAT-67).
    private(set) static var storeError: Error?

    static let services: AppServices = {
        let clock: Clock = launch.fixedNow.map { FixedClock(now: $0) } ?? SystemClock()
        let container: ModelContainer
        if launch.isInMemory {
            container = Database.makeInMemoryContainer()
        } else {
            do {
                // Перше відкриття новою схемою — спершу копія файлів: міграція їх переписує (WAT-67).
                Database.backupIfSchemaChanged(now: clock.now)
                container = try Database.makeContainer()
            } catch {
                AppLog.persistence.error("store: \(error)")
                storeError = error
                container = Database.makeInMemoryContainer()
            }
        }
        // Без свого сховища — нічого назовні: системні сповіщення й знімок віджетів лишаються від останнього
        // вдалого запуску. e2e не бачать системних запитів: центр у пам'яті з дозволом, заданим прапорцем.
        let isolated = launch.isUITest || storeError != nil
        let center: NotificationCenterProtocol = isolated
            ? InMemoryNotificationCenter(status: launch.notificationAuthorization)
            : SystemNotificationCenter()
        let services = AppServices(
            container: container, clock: clock, notificationCenter: center,
            bubbleSoundAvailable: Bundle.main.url(forResource: "drop", withExtension: "caf") != nil,
            xpRules: xpRules,
            // e2e — база в пам'яті: справжній знімок віджетів у App Group вона не переписує.
            widgetStore: isolated ? WidgetSnapshotStore(url: nil) : .shared,
            widgetReloader: isolated ? nil : WidgetCenterReloader(),
            widgetPicker: isolated ? nil : .shared
        )
        // До `bootstrap()`: завдання видаються першою ж подією дня — стартовим перерахунком.
        services.gamification.questForcing = launch.quests
        // Демо-історія старша за 8 днів — несподіване від пікера перекрило б чужі сценарії. Лише `--quests surprise:…`.
        services.gamification.surprisesEnabled = !launch.isUITest
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
        // e2e не мають залежати від того, що лишилось у налаштуваннях симулятора з ручної перевірки.
        if let design = launch.onboardingDesign ?? (launch.isUITest ? .scene : nil) {
            OnboardingDesign.current = design
        }
        return services
    }()

    /// Онбординг на старті: прапорець e2e або перший запуск без жодної порції (SPEC-ONBOARDING §8). Під `--uitest-*` —
    /// лише за прапорцем, інакше він перекрив би всі наявні сценарії.
    static let onboardingOnLaunch: OnboardingMode? = launch.onboarding
        ?? (!launch.isUITest && storeError == nil && services.shouldOpenOnboarding ? .firstRun : nil)

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
