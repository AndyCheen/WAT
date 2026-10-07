import XCTest
import SwiftData
import Core
import Persistence
import Insights
import Gamification
import Notifications
@testable import Features

/// Перемикач «Ритм дня» (WAT-42, SPEC-NOTIFICATIONS §28): вимкнено — режим «просто норма за день».
/// Розклад за замовчуванням — 08:00–22:00, норма 2000 мл: цілі частин 689, 826 і 485 мл.
@MainActor
final class DayRhythmFeatureTests: XCTestCase {
    private var clock: FixedClock!
    private var services: AppServices!

    /// 1 жовтня 2026 (четвер), за Києвом.
    private static func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 1; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: parts)!
    }

    override func setUp() async throws {
        try await super.setUp()
        clock = FixedClock(now: Self.date(7))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock,
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    private func add(_ ml: Int, at hour: Int, _ minute: Int = 0, to model: HomeViewModel) {
        clock.set(Self.date(hour, minute))
        model.add(ml)
    }

    private func planToday() async -> [PlannedNotification] {
        await services.notifications.rescheduleNow()
        return services.notifications.lastPlan.items.filter { $0.dayKey == services.calendar.today }
    }

    private var dayPartXp: [XPEntry] {
        GamificationStore(context: services.container.mainContext).xpEntries(reason: .dayPartGoal).filter { $0.revertedAt == nil }
    }

    // MARK: - Критерії приймання

    /// За день із порціями без ритму: ні чекпоінтів, ні XP `dayPartGoal`, а звіт і текст денного
    /// сповіщення — без частин доби.
    func testPlainDayHasNoDayPartsAnywhere() async {
        let model = HomeViewModel(services: services)
        SettingsModel(services: services).setDayRhythm(false)
        add(250, at: 8, 30, to: model)
        clock.set(Self.date(9))

        let plan = await planToday()
        XCTAssertFalse(plan.contains { $0.type == .checkpoint })
        XCTAssertTrue(plan.contains { $0.type == .reminder }, "нагадування лишаються")
        let report = plan.first { $0.type == .report }
        XCTAssertNotNil(report)
        XCTAssertFalse(report?.body.contains("найслабше") ?? true, report?.body ?? "")

        add(700, at: 11, to: model)
        XCTAssertTrue(dayPartXp.isEmpty, "950 ≥ 689, але режим «просто норма»")
        XCTAssertNil(model.dayPartLine(), "капсули на головному немає")

        let slides = presenter(for: .day(services.calendar.today)).slides
        guard case let .timeline(kicker, title, blocks, drops, _, rows, foot) = slides[1] else { return XCTFail("\(slides[1])") }
        XCTAssertEqual(kicker, "Випито за день")
        XCTAssertEqual(title, "2 порції за день")
        XCTAssertTrue(blocks.isEmpty)
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(drops.count, 2)
        XCTAssertEqual(foot, "Перша — о 08:30, остання — о 11:00. У середньому 475 мл за раз.")
        guard case let .thought(_, _, headline, _, _) = slides.last else { return XCTFail("\(String(describing: slides.last))") }
        XCTAssertFalse(headline.contains("частина"), headline)
    }

    /// Увімкнення назад повертає все з наступної порції; нарахованого раніше вимкнення не забирає.
    func testTurningBackOnResumesFromNextPortion() async {
        let model = HomeViewModel(services: services)
        let settings = SettingsModel(services: services)
        add(700, at: 9, to: model)
        XCTAssertEqual(dayPartXp.count, 1)

        settings.setDayRhythm(false)
        XCTAssertEqual(dayPartXp.count, 1, "вимкнення XP не відкочує")
        add(500, at: 13, to: model)
        add(300, at: 14, to: model)
        XCTAssertEqual(dayPartXp.count, 1)

        settings.setDayRhythm(true)
        XCTAssertNotNil(model.dayPartLine())
        add(100, at: 15, to: model)
        XCTAssertEqual(dayPartXp.count, 2, "блок 12–17 закрито — XP з наступної порції")
    }

    /// Тиждень і місяць без ритму — без слайда «Ритм доби» / «Що змінилось».
    func testWeekAndMonthDropRhythmSlide() {
        let model = HomeViewModel(services: services)
        add(700, at: 9, to: model)
        add(800, at: 13, to: model)
        add(600, at: 19, to: model)
        let week = services.calendar.period(.week, containing: services.calendar.today)
        let month = services.calendar.period(.month, containing: services.calendar.today)

        func hasRhythm(_ period: ReportPeriod) -> Bool {
            presenter(for: period).slides.contains { if case .rhythm = $0 { true } else { false } }
        }
        XCTAssertTrue(hasRhythm(week))
        XCTAssertTrue(hasRhythm(month))

        SettingsModel(services: services).setDayRhythm(false)
        XCTAssertFalse(hasRhythm(week))
        XCTAssertFalse(hasRhythm(month))
        XCTAssertTrue(presenter(for: week).slides.contains { if case .weekGoals = $0 { true } else { false } },
                      "дні з нормою лишаються")
    }

    // MARK: - Пропозиція «Рівні інтервали»

    func testTurningOffOffersIntervalRemindersOnce() {
        let model = SettingsModel(services: services)
        model.setDayRhythm(false)
        XCTAssertTrue(model.offersIntervalReminders, "«За темпом» спирається на частини доби")

        model.switchRemindersToInterval()
        XCTAssertEqual(services.notifications.settings.reminderMode, .interval)
        XCTAssertFalse(model.offersIntervalReminders)

        model.setDayRhythm(true)
        model.setDayRhythm(false)
        XCTAssertFalse(model.offersIntervalReminders, "уже рівні інтервали — пропонувати нічого")
    }

    func testNoOfferWhenRemindersAreOff() {
        services.notifications.settings.remindersEnabled = false
        let model = SettingsModel(services: services)
        model.setDayRhythm(false)
        XCTAssertFalse(model.offersIntervalReminders)
    }

    func testOfferGoesAwayWhenLeavingScreen() {
        let model = SettingsModel(services: services)
        model.setDayRhythm(false)
        model.dismissOffers()
        XCTAssertFalse(model.offersIntervalReminders, "пропозиція — лише щойно після вимикання")
        XCTAssertEqual(services.notifications.settings.reminderMode, .pace, "мовчки нічого не змінюємо")
    }

    private func presenter(for period: ReportPeriod) -> ReportPresenter {
        let calendar = services.calendar
        return ReportPresenter(
            report: services.insights.report(for: period),
            game: services.gamification.periodSummary(days: calendar.days(in: period)),
            streak: services.gamification.streakSummary(),
            recentGoalDays: Array(repeating: false, count: 7),
            schedule: services.profile.schedule(isWeekend: false),
            weekendScheduleEnabled: false,
            dayPartXp: 10,
            today: calendar.today,
            tomorrowMorning: nil,
            nowMinute: nil,
            calendar: calendar
        )
    }
}
