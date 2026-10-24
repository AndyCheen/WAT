import XCTest
import Core
import Persistence
import Metrics
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
        settings.stepGoal(up: true)
        XCTAssertEqual(settings.goalMl, 2100, "крок — 100 мл")
        XCTAssertEqual(settings.goalLabel, "2.1 л")

        home.reload()
        XCTAssertEqual(home.day.goalMl, 2100)
        XCTAssertEqual(home.pctLabel, "24%")
    }

    func testThemeAndHapticsArePersisted() {
        let settings = SettingsModel(services: services)
        settings.setThemeMode(.dark)
        settings.setHaptics(false)
        XCTAssertEqual(services.profile.themeMode, .dark)
        XCTAssertFalse(services.profile.hapticsEnabled)
    }

    /// «Темна сторона» — лише вибір «Темна» тут (WAT-60): «Як у системі» його не дає, навіть у темній системі.
    func testDarkSideIsTheChoiceNotTheSystem() {
        let settings = SettingsModel(services: services)
        let dark = { self.services.gamification.achievementSnapshots().first { $0.key == "discover.dark" }?.isUnlocked }
        settings.setThemeMode(.system)
        XCTAssertEqual(dark(), false)
        settings.setThemeMode(.dark)
        XCTAssertEqual(dark(), true)
    }

    /// Три сегменти (WAT-66): до «Системної» можна повернутись, а повторний тап по вибраному — не зміна теми.
    func testSystemThemeIsReachableAndRepeatIsNotAChange() {
        let settings = SettingsModel(services: services)
        let changes = { self.services.metrics.events(.themeChanged).count }
        XCTAssertEqual(services.profile.themeMode, .system, "типова — системна")
        XCTAssertEqual(SettingsModel.themeModes.map(SettingsModel.themeTitle), ["Світла", "Темна", "Системна"])

        settings.setThemeMode(.dark)
        settings.setThemeMode(.dark)
        XCTAssertEqual(changes(), 1)
        settings.setThemeMode(.system)
        XCTAssertEqual(services.profile.themeMode, .system)
        XCTAssertEqual(changes(), 2)
    }
}
