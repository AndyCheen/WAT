import XCTest
import SwiftData
import Core
import Persistence
import Insights
import Notifications
@testable import Features

/// Вікно «Графік дня» (WAT-41, SPEC-NOTIFICATIONS §27). «Сьогодні» — понеділок 5 жовтня 2026, 12:00
/// за Києвом; графік за замовчуванням — 08:00–22:00.
@MainActor
final class ScheduleFeatureTests: XCTestCase {
    private var clock: FixedClock!
    private var center: InMemoryNotificationCenter!
    private var services: AppServices!

    private static let kyiv = TimeZone(identifier: "Europe/Kyiv")!

    private static func date(_ day: DayKey, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kyiv
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
    }

    override func setUp() async throws {
        try await super.setUp()
        clock = FixedClock(now: Self.date(DayKey(rawValue: "2026-10-05"), 12))
        center = InMemoryNotificationCenter()
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)
        services.bootstrap()
    }

    /// 14 днів до сьогодні, 10 із них — з першою склянкою о `first`.
    private func seedWindow(first: (hour: Int, minute: Int) = (6, 30)) {
        let calendar = services.calendar
        for offset in 1...14 where ![3, 6, 10, 13].contains(offset) {
            let day = calendar.dayKey(offsetDays: -offset, from: calendar.today)
            services.hydration.addIntake(amountMl: 250, source: .seed, at: Self.date(day, first.hour, first.minute))
            services.hydration.addIntake(amountMl: 500, source: .seed, at: Self.date(day, 13))
            services.hydration.addIntake(amountMl: 300, source: .seed, at: Self.date(day, 20, 30))
        }
    }

    private func moveDays(_ days: Int) {
        clock.set(clock.now.addingTimeInterval(TimeInterval(days * 86_400)))
    }

    private func openApp(_ model: HomeViewModel, activation: Int) {
        model.offerScheduleIfNeeded(activation: activation, isHomeOnTop: true)
    }

    // MARK: - Критерії приймання

    /// 10 днів із першою порцією ≈ 06:30 при підйомі 08:00 — при відкритті один раз з'являється вікно з 06:30.
    func testOfferAppearsOnceOnOpen() throws {
        seedWindow()
        let model = HomeViewModel(services: services)
        openApp(model, activation: 1)
        XCTAssertEqual(model.sheet, .schedule)
        let content = try XCTUnwrap(model.scheduleContent)
        XCTAssertEqual(content.title, "Змінити підйом?")
        XCTAssertEqual(content.subtitle, "Останні 2 тижні ти починаєш пити раніше")
        XCTAssertEqual(content.changes.map(\.new), ["06:30"])
        XCTAssertEqual(content.changes.map(\.old), ["08:00"])

        // ✕ — без відповіді. Наступне відкриття того ж дня вікна вже не показує, через 7 днів — так.
        model.closeSchedule()
        openApp(model, activation: 2)
        XCTAssertNil(model.sheet)
        XCTAssertEqual(services.profile.scheduleOfferOutcome, .dismissed)

        moveDays(7)
        seedWindow()
        openApp(model, activation: 3)
        XCTAssertEqual(model.sheet, .schedule)
    }

    /// «Так» міняє підйом, план сповіщень перебудовується, минулі дні й звіти не змінюються.
    func testAcceptChangesWakeReschedulesAndKeepsPast() async throws {
        seedWindow()
        services.hydration.addIntake(amountMl: 250, source: .seed, at: Self.date(services.calendar.today, 9))
        let pastDay = services.calendar.dayKey(offsetDays: -1, from: services.calendar.today)
        let reportBefore = services.insights.report(for: .day(pastDay), withThought: false)

        let model = HomeViewModel(services: services)
        openApp(model, activation: 1)
        model.acceptSchedule()

        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.toast?.message, "Графік оновлено: 06:30–22:00")
        XCTAssertEqual(services.profile.wakeMinutes, 390)
        XCTAssertFalse(services.profile.weekendScheduleEnabled)
        XCTAssertEqual(services.profile.scheduleOfferOutcome, .accepted)

        XCTAssertEqual(services.dayLogs.existingDayLog(for: services.calendar.today)?.wakeMinutesSnapshot, 390,
                       "сьогоднішні цілі частин доби — за новим графіком")
        XCTAssertEqual(services.dayLogs.existingDayLog(for: pastDay)?.wakeMinutesSnapshot, 480, "минулий день не чіпаємо")
        XCTAssertEqual(services.insights.report(for: .day(pastDay), withThought: false), reportBefore)

        await services.notifications.rescheduleNow()
        let tomorrow = services.calendar.dayKey(offsetDays: 1, from: services.calendar.today)
        let morning = try XCTUnwrap(center.scheduled.first { $0.identifier.hasPrefix("wt.morning.\(tomorrow.rawValue)") })
        XCTAssertEqual(morning.fireAt, Self.date(tomorrow, 6, 30), "ранкова склянка — о новому підйомі")
    }

    /// «Ні» — вікно не з'являється 60 днів.
    func testDeclineSilencesForSixtyDays() {
        seedWindow()
        let model = HomeViewModel(services: services)
        openApp(model, activation: 1)
        model.declineSchedule()
        XCTAssertNil(model.sheet)
        XCTAssertEqual(services.profile.wakeMinutes, 480)

        moveDays(59)
        seedWindow()
        XCTAssertNil(services.scheduleOffer())
        moveDays(1)
        seedWindow()
        XCTAssertNotNil(services.scheduleOffer())
    }

    /// Після «Ні» раніше 60 днів — лише якщо звичка відійшла ще на годину, і не раніше ніж за 30.
    func testDeclinedOfferReturnsEarlierWhenShiftGrows() {
        seedWindow()
        let model = HomeViewModel(services: services)
        openApp(model, activation: 1)
        model.declineSchedule()

        moveDays(30)
        seedWindow(first: (6, 15))
        XCTAssertNil(services.scheduleOffer(), "зсув 105 хв проти 90 — виріс менше ніж на годину")
        seedWindow(first: (5, 0))
        XCTAssertEqual(services.scheduleOffer()?.proposed.wakeMinutes, 300, "180 хв — на годину більше")
    }

    // MARK: - Дії у вікні

    func testAdjustThenSave() throws {
        services.showScheduleSuggestion(.wakeEarly)
        let model = HomeViewModel(services: services)
        model.apply(try XCTUnwrap(services.router.takeHomeIntent()))
        XCTAssertEqual(model.sheet, .schedule)

        model.adjustSchedule()
        XCTAssertTrue(model.scheduleAdjusting)
        model.stepScheduleWake(1)
        model.stepScheduleSleep(1)
        XCTAssertEqual(model.scheduleContent?.changes.map(\.new), ["06:45"], "рядки — лише межі з пропозиції")
        model.acceptSchedule()

        XCTAssertEqual(model.toast?.message, "Графік оновлено: 06:45–22:15")
        XCTAssertEqual(services.profile.wakeMinutes, 405)
        XCTAssertEqual(services.profile.sleepMinutes, 1335)
    }

    /// Кроки — у межах екрана «Сповіщення»: підйом від 04:00, активних годин ≥ 6.
    func testAdjustStaysWithinBounds() throws {
        services.showScheduleSuggestion(.wakeEarly)
        let model = HomeViewModel(services: services)
        model.apply(try XCTUnwrap(services.router.takeHomeIntent()))
        model.adjustSchedule()
        for _ in 0..<20 { model.stepScheduleWake(-1) }
        XCTAssertEqual(model.scheduleDraft.wakeMinutes, 240)
        for _ in 0..<80 { model.stepScheduleWake(1) }
        XCTAssertEqual(model.scheduleDraft.wakeMinutes, 1320 - 360)
    }

    /// Зсув лише у вихідні — «Так» вмикає окремий розклад вихідних, будні лишаються.
    func testWeekendSuggestionEnablesWeekendSchedule() throws {
        services.showScheduleSuggestion(.weekend)
        let model = HomeViewModel(services: services)
        model.apply(try XCTUnwrap(services.router.takeHomeIntent()))
        XCTAssertEqual(model.scheduleContent?.scope, "Лише вихідні")
        model.acceptSchedule()

        XCTAssertEqual(model.toast?.message, "Графік вихідних оновлено: 10:00–22:00")
        let profile = services.profile
        XCTAssertTrue(profile.weekendScheduleEnabled)
        XCTAssertEqual(profile.weekendWakeMinutes, 600)
        XCTAssertEqual(profile.weekendSleepMinutes, 1320)
        XCTAssertEqual(profile.wakeMinutes, 480)
    }

    // MARK: - Коли не показувати

    /// Не поверх шторки, тоста, картки чи переходу зі сповіщення, не під іншим екраном — і раз на відкриття.
    func testOfferWaitsForCleanHome() throws {
        seedWindow()
        let model = HomeViewModel(services: services)

        model.offerScheduleIfNeeded(activation: 1, isHomeOnTop: false)
        XCTAssertNil(model.sheet, "головний під іншим екраном")

        model.present(.custom)
        openApp(model, activation: 2)
        XCTAssertEqual(model.sheet, .custom)
        model.dismissSheet()

        services.router.open(.glass)
        openApp(model, activation: 3)
        XCTAssertNil(model.sheet, "тап по сповіщенню вже веде у «Склянку»")
        _ = services.router.takeHomeIntent()
        _ = services.router.takePath()

        model.add(250)
        model.remove(id: try XCTUnwrap(model.history.first?.id))
        XCTAssertEqual(model.toast?.message, "Порцію видалено")
        openApp(model, activation: 4)
        XCTAssertNotEqual(model.sheet, .schedule, "тост ще на екрані")
        model.dismissToast()

        openApp(model, activation: 4)
        XCTAssertNil(model.sheet, "те саме відкриття вдруге не перевіряється")
        openApp(model, activation: 5)
        XCTAssertEqual(model.sheet, .schedule)
        XCTAssertEqual(services.profile.scheduleOfferOutcome, .dismissed, "показ записано одразу")
    }

    /// Демо-історія e2e свого вікна не показує, інакше воно перекривало б чужі сценарії.
    func testDemoHistoryDoesNotOffer() {
        FixtureSeeder.seed(into: services)
        XCTAssertNil(services.scheduleOffer())
    }

    /// `--seed-schedule-shift` — критерій приймання для e2e: вікно з 06:30 саме.
    func testScheduleShiftSeedOffersSixThirty() {
        FixtureSeeder.seedScheduleShift(into: services)
        XCTAssertEqual(services.scheduleOffer()?.proposed, DaySchedule(wakeMinutes: 390, sleepMinutes: 1320))
    }

    // MARK: - Тексти

    func testPresenterTexts() {
        let weekday = DaySchedule(wakeMinutes: 480, sleepMinutes: 1320)
        func content(_ scope: ScheduleSuggestion.Scope, _ proposed: DaySchedule) -> SchedulePresenter.Content {
            SchedulePresenter.content(ScheduleSuggestion(scope: scope, current: weekday, proposed: proposed), draft: proposed)
        }

        let late = content(.everyDay, DaySchedule(wakeMinutes: 585, sleepMinutes: 1320))
        XCTAssertEqual(late.glyph, "☀️")
        XCTAssertNil(late.scope)
        XCTAssertEqual(late.subtitle, "Останні 2 тижні ти починаєш пити пізніше")
        XCTAssertEqual(late.changes.first?.accessibilityLabel, "Підйом: було 08:00, стане 09:45")

        let evening = content(.everyDay, DaySchedule(wakeMinutes: 480, sleepMinutes: 1260))
        XCTAssertEqual(evening.glyph, "🌙")
        XCTAssertEqual(evening.title, "Змінити відбій?")
        XCTAssertEqual(evening.subtitle, "Останні 2 тижні ти закінчуєш пити раніше")

        let both = content(.weekdaysOnly, DaySchedule(wakeMinutes: 390, sleepMinutes: 1395))
        XCTAssertEqual(both.title, "Змінити графік?")
        XCTAssertEqual(both.scope, "Лише будні")
        XCTAssertEqual(both.subtitle, "Останні 2 тижні в будні ти починаєш пити раніше, а закінчуєш пізніше")
        XCTAssertEqual(both.changes.map(\.new), ["06:30", "23:15"])

        let weekend = content(.weekends, DaySchedule(wakeMinutes: 600, sleepMinutes: 1320))
        XCTAssertEqual(weekend.subtitle, "Останні два вихідні ти починаєш пити пізніше")

        // Час — лише в рядках «08:00 → 06:30», а не в заголовку й реченні; без родового минулого часу (§14.1).
        for text in [late, evening, both, weekend].flatMap({ [$0.title, $0.subtitle] }) {
            XCTAssertFalse(text.contains(":"), "час у тексті: \(text)")
            XCTAssertFalse(text.contains("пив") || text.contains("пила"), text)
        }
    }
}
