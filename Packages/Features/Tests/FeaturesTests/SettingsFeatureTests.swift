import XCTest
import Core
import Persistence
import Notifications
@testable import Features

/// Екран «Налаштування» (WAT-15): мета змінюється тут, а головний бачить її після повернення.
@MainActor
final class SettingsFeatureTests: XCTestCase {
    private var services: AppServices!

    override func setUp() async throws {
        try await super.setUp()
        services = AppServices(container: Database.makeInMemoryContainer(),
                               clock: FixedClock(now: Date(timeIntervalSince1970: 1_790_000_000)),
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    func testGoalStepRecalculatesHomeOnReturn() {
        let home = HomeViewModel(services: services)
        home.reload()
        home.add(500)

        let settings = SettingsModel(services: services)
        XCTAssertEqual(settings.goalLabel, "2.0 л")
        settings.changeGoal(by: 250)
        XCTAssertEqual(settings.goalMl, 2250)
        XCTAssertEqual(settings.goalLabel, "2.2 л", "2250 мл → «2.2 л», як і було в шторці")

        home.reload()
        XCTAssertEqual(home.day.goalMl, 2250)
        XCTAssertEqual(home.pctLabel, "22%")
    }

    func testThemeAndHapticsArePersisted() {
        let settings = SettingsModel(services: services)
        settings.setThemeMode(.dark)
        settings.setHaptics(false)
        XCTAssertEqual(services.profile.themeMode, .dark)
        XCTAssertFalse(services.profile.hapticsEnabled)
    }
}
