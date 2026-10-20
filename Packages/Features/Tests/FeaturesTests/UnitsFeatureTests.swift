import XCTest
import SwiftData
import Core
import Persistence
import Insights
import Notifications
import Widgets
@testable import Features

/// Одиниці в «Налаштуваннях» (WAT-58): вага й формат часу перемикаються там само, як об'єм, і показ одразу
/// йде за ними — головний, «Сповіщення», «Графік дня», звіт, «Знання», віджети. Об'єм — `VolumeUnitFeatureTests`.
/// «Сьогодні» — 1 жовтня 2026, 10:00 за Києвом.
@MainActor
final class UnitsFeatureTests: XCTestCase {
    private var services: AppServices!

    override func setUp() async throws {
        try await super.setUp()
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 1; parts.hour = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        services = AppServices(container: Database.makeInMemoryContainer(),
                               clock: FixedClock(now: calendar.date(from: parts)!),
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    // MARK: - Перемикання

    func testSettingsSwitchMassAndTimeFormat() {
        let settings = SettingsModel(services: services)
        XCTAssertEqual(settings.massUnit, .kilograms)
        XCTAssertEqual(settings.timeFormat, .hours24)

        settings.setMassUnit(.pounds)
        settings.setTimeFormat(.hours12)
        XCTAssertEqual(services.profile.massUnit, .pounds)
        XCTAssertEqual(services.profile.timeFormat, .hours12)
        XCTAssertEqual(services.notifications.preferences().timeFormat, .hours12, "тексти сповіщень — у новому форматі")

        settings.setTimeFormat(.hours24)
        XCTAssertEqual(services.notifications.preferences().timeFormat, .hours24)
    }

    /// Рядки й варіанти — ті самі, що на кроці «Одиниці» онбордингу: людина впізнає вибір.
    func testSettingsRowsMatchOnboarding() {
        XCTAssertEqual(OnboardingPresenter.unitRows.map(\.title), ["Об'єм", "Вага", "Час"])
        XCTAssertEqual(OnboardingPresenter.unitRows.map(\.options),
                       [["Мілілітри", "Унції"], ["Кілограми", "Фунти"], ["24 години", "12 годин"]])
    }

    // MARK: - Час

    func testHomeInTwelveHours() throws {
        SettingsModel(services: services).setTimeFormat(.hours12)
        let home = HomeViewModel(services: services)
        home.add(250)
        XCTAssertEqual(home.history.first?.timeLabel, "10:00 дп", "час порції в історії")

        let line = try XCTUnwrap(home.dayPartLine())
        guard case .pending(_, let title, _, _) = line.content else { return XCTFail("капсула має бути «ще…»") }
        XCTAssertTrue(title.hasPrefix("До 12:00 пп — ще "), title)
        XCTAssertTrue(line.accessibilityLabel.hasPrefix("До 12:00 пп бракує "), line.accessibilityLabel)
    }

    func testNotificationsScreenInTwelveHours() {
        let model = NotificationsSettingsModel(services: services)
        XCTAssertEqual(model.time(22 * 60), "22:00")
        SettingsModel(services: services).setTimeFormat(.hours12)
        XCTAssertEqual(model.time(22 * 60), "10:00 пп")
        XCTAssertEqual(model.time(8 * 60), "8:00 дп")
    }

    func testScheduleWindowInTwelveHours() {
        let weekday = DaySchedule.weekdayDefault
        var proposed = weekday
        proposed.wakeMinutes = 6 * 60 + 30
        let suggestion = ScheduleSuggestion(scope: .everyDay, current: weekday, proposed: proposed)
        let content = SchedulePresenter.content(suggestion, draft: proposed, format: .hours12)
        XCTAssertEqual(content.changes.map(\.old), ["8:00 дп"])
        XCTAssertEqual(content.changes.map(\.new), ["6:30 дп"])
        XCTAssertEqual(content.changes.first?.accessibilityLabel, "Підйом: було 8:00 дп, стане 6:30 дп")
        XCTAssertEqual(SchedulePresenter.toast(suggestion, schedule: proposed, format: .hours12),
                       "Графік оновлено: 6:30 дп–10:00 пп")
        XCTAssertEqual(SchedulePresenter.toast(suggestion, schedule: proposed), "Графік оновлено: 06:30–22:00")
    }

    func testReportAndEvennessInTwelveHours() {
        SettingsModel(services: services).setTimeFormat(.hours12)
        XCTAssertEqual(ReportFormat.clock(24 * 60, .hours12), "12:00 дп", "відбій опівночі")
        XCTAssertEqual(ReportFormat.clock(24 * 60), "00:00")
        let stats = StatsViewModel(services: services)
        XCTAssertEqual(stats.evenness.rows.first.map { $0.hoursLabel(stats.timeFormat) }, "8 дп–12 пп")
    }

    func testLearnAndPrizesFollowTheSystem() {
        let settings = SettingsModel(services: services)
        settings.setTimeFormat(.hours12)
        settings.setVolumeUnit(.usFluidOunces)

        let context = services.learnContext()
        XCTAssertEqual(context.timeFormat, .hours12)
        XCTAssertEqual(context.volumeUnit, .usFluidOunces)
        let start = LearnPresenter(context: context).slides(for: LearnCatalog.story("app.start")!)
        let pill = start.compactMap { slide -> String? in
            if case .dayPartPill(let title, _, _) = slide.visual { return title }
            return nil
        }.first
        XCTAssertEqual(pill, "До 12:00 пп — ще 10 унц.")

        XCTAssertEqual(PrizeInventoryModel(services: services).presenter.clockTime(nil), "12:00 дп")
    }

    // MARK: - Віджети

    /// Знімок для віджетів несе систему людини: після перемикання тексти віджетів — в унціях і 12 годинах.
    func testWidgetSnapshotCarriesTheSystem() throws {
        let settings = SettingsModel(services: services)
        settings.setVolumeUnit(.usFluidOunces)
        settings.setTimeFormat(.hours12)
        let snapshot = services.makeWidgetSnapshot(plan: .empty, planIsCurrent: false)
        XCTAssertEqual(snapshot.volumeUnit, .usFluidOunces)
        XCTAssertEqual(snapshot.timeFormat, .hours12)

        let day = WidgetDay.resolve(snapshot, at: services.calendar.now, calendar: services.calendar)
        XCTAssertEqual(WidgetPresenter.part(day, xp: 10).headline, "ще до 12:00 пп")
        XCTAssertTrue(WidgetPresenter.todayFootnote(day).hasSuffix(" унц."), WidgetPresenter.todayFootnote(day))
    }

    // MARK: - Вага

    func testCalculatorWeightInPounds() {
        SettingsModel(services: services).setMassUnit(.pounds)
        let stats = StatsViewModel(services: services)
        stats.weightKg = 70
        XCTAssertEqual(stats.weightLabel, "154 фунти")
        stats.stepWeight(1)
        XCTAssertEqual(stats.weightLabel, "155 фунтів", "крок — фунт, від показаного числа")
        stats.stepWeight(-2)
        XCTAssertEqual(stats.weightLabel, "153 фунти")
        XCTAssertEqual(stats.weightKg, Mass.kilograms(153, from: .pounds), accuracy: 0.001, "у профілі — кілограми")

        SettingsModel(services: services).setMassUnit(.kilograms)
        XCTAssertEqual(stats.weightLabel, "69 кг")
    }
}
