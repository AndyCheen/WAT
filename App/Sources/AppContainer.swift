import Foundation
import SwiftData
import Core
import Persistence
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
            bubbleSoundAvailable: Bundle.main.url(forResource: "drop", withExtension: "caf") != nil
        )
        services.bootstrap()
        if launch.seedsDemoData {
            FixtureSeeder.seed(into: services)
        }
        if let tap = launch.notificationTap {
            services.simulateNotificationTap(tap)
        }
        return services
    }()
}
