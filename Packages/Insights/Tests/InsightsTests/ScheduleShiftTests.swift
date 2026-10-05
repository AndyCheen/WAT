import XCTest
import SwiftData
import Core
import Persistence
import Metrics
@testable import Insights

/// Пропозиція графіка (WAT-41, SPEC-NOTIFICATIONS §27). Вікно — 14 днів до понеділка 5 жовтня 2026:
/// пн 21.09 … нд 04.10, вихідні — індекси 5, 6, 12, 13. Графік за замовчуванням — 08:00–22:00.
final class ScheduleShiftTests: XCTestCase {
    private static let weekendIndices: Set<Int> = [5, 6, 12, 13]
    private static let standard = WeekSchedule(
        weekday: DaySchedule(wakeMinutes: 480, sleepMinutes: 1320), weekendEnabled: false,
        weekend: DaySchedule(wakeMinutes: 540, sleepMinutes: 1380)
    )

    /// День — перша й остання склянка плюс одна посередині; `nil` — день без порцій.
    private func window(_ spec: [(first: Int, last: Int)?]) -> [ScheduleDay] {
        precondition(spec.count == 14)
        return spec.enumerated().map { index, day in
            ScheduleDay(isWeekend: Self.weekendIndices.contains(index),
                        intakeMinutes: day.map { [$0.first, ($0.first + $0.last) / 2, $0.last] } ?? [])
        }
    }

    /// Будні й вихідні окремо — для сценаріїв, де вони живуть по-різному.
    private func window(weekdays: (first: Int, last: Int), weekends: (first: Int, last: Int)?) -> [ScheduleDay] {
        window((0..<14).map { Self.weekendIndices.contains($0) ? weekends : weekdays })
    }

    private func suggest(_ days: [ScheduleDay], _ week: WeekSchedule = standard) -> ScheduleSuggestion? {
        ScheduleShift.suggest(days: days, current: week)
    }

    // MARK: - Критерії приймання

    /// 10 днів із першою порцією ≈ 06:30 при підйомі 08:00 — пропозиція 06:30.
    func testEarlyRiserGetsSixThirty() throws {
        let days = window([nil, (385, 1260), (395, 1250), (380, 1270), nil, (390, 1240), (400, 1255),
                           nil, (375, 1265), (390, 1245), nil, (395, 1250), (385, 1260), (390, 1230)])
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.scope, .everyDay)
        XCTAssertEqual(suggestion.current, DaySchedule(wakeMinutes: 480, sleepMinutes: 1320))
        XCTAssertEqual(suggestion.proposed, DaySchedule(wakeMinutes: 390, sleepMinutes: 1320))
        XCTAssertEqual(suggestion.shiftMinutes, 90)
    }

    /// 3 ранні дні з 10 — шум, вікна немає.
    func testThreeEarlyDaysOfTenIsNoise() {
        let days = window([nil, (385, 1260), (500, 1250), (510, 1270), nil, (495, 1240), (390, 1255),
                           nil, (520, 1265), (505, 1245), nil, (380, 1250), (515, 1260), (490, 1230)])
        XCTAssertNil(suggest(days))
    }

    /// Зсув лише у вихідні — окремий розклад вихідних, будні не чіпаються.
    func testWeekendOnlyShiftEnablesWeekendSchedule() throws {
        let days = window(weekdays: (490, 1250), weekends: (600, 1260))
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.scope, .weekends)
        XCTAssertEqual(suggestion.current, DaySchedule(wakeMinutes: 480, sleepMinutes: 1320))
        XCTAssertEqual(suggestion.proposed, DaySchedule(wakeMinutes: 600, sleepMinutes: 1320))

        let applied = suggestion.applying(suggestion.proposed, to: Self.standard)
        XCTAssertTrue(applied.weekendEnabled)
        XCTAssertEqual(applied.weekend, DaySchedule(wakeMinutes: 600, sleepMinutes: 1320))
        XCTAssertEqual(applied.weekday, Self.standard.weekday)
    }

    // MARK: - Обидва боки

    func testLateFirstGlassMovesWakeLater() throws {
        let days = window([(590, 1250), (580, 1260), nil, (600, 1240), (585, 1255), (575, 1250), nil,
                           (595, 1245), (590, 1260), (470, 1250), (585, 1265), nil, (580, 1255), (600, 1250)])
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.scope, .everyDay)
        XCTAssertEqual(suggestion.proposed, DaySchedule(wakeMinutes: 585, sleepMinutes: 1320))
    }

    func testLateLastGlassMovesSleepLater() throws {
        let days = window(weekdays: (490, 1395), weekends: (495, 1400))
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.proposed, DaySchedule(wakeMinutes: 480, sleepMinutes: 1395))
    }

    /// Остання склянка о 19:00 при відбої 22:00 — це понад нормальну паузу 2 год: відбій = 19:00 + 2 год.
    func testEarlyLastGlassBeyondPauseMovesSleepEarlier() throws {
        let days = window(weekdays: (490, 1140), weekends: (500, 1135))
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.proposed, DaySchedule(wakeMinutes: 480, sleepMinutes: 1260))
    }

    /// Перестати пити за 1–2 год до сну нормально (§13.6) — і навіть 2,5 год ще в межах запасу.
    func testEveningPauseIsNotAShift() {
        XCTAssertNil(suggest(window(weekdays: (490, 1200), weekends: (500, 1230))))
        XCTAssertNil(suggest(window(weekdays: (490, 1170), weekends: (500, 1170))))
    }

    func testBothEndsAtOnce() throws {
        let days = window(weekdays: (390, 1395), weekends: (395, 1400))
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.proposed, DaySchedule(wakeMinutes: 390, sleepMinutes: 1395))
        XCTAssertEqual(suggestion.shiftMinutes, 90)
    }

    // MARK: - Будні й вихідні

    /// Будні раніше, а вихідні з даними — як були: вихідні лишаються зі старими часами,
    /// інакше застосунок будив би о 06:30 у суботу.
    func testWeekdayShiftKeepsSteadyWeekends() throws {
        let days = window(weekdays: (390, 1250), weekends: (500, 1260))
        let suggestion = try XCTUnwrap(suggest(days))
        XCTAssertEqual(suggestion.scope, .weekdaysOnly)

        let applied = suggestion.applying(suggestion.proposed, to: Self.standard)
        XCTAssertEqual(applied.weekday, DaySchedule(wakeMinutes: 390, sleepMinutes: 1320))
        XCTAssertTrue(applied.weekendEnabled)
        XCTAssertEqual(applied.weekend, DaySchedule(wakeMinutes: 480, sleepMinutes: 1320))
    }

    /// Двох вихідних замало, щоб вважати їх іншими, — вони йдуть за буднями.
    func testWeekendsWithoutEnoughDataFollowWeekdays() throws {
        var spec: [(first: Int, last: Int)?] = (0..<14).map { Self.weekendIndices.contains($0) ? (500, 1260) : (390, 1250) }
        spec[12] = nil
        spec[13] = nil
        let suggestion = try XCTUnwrap(suggest(window(spec)))
        XCTAssertEqual(suggestion.scope, .everyDay)
        XCTAssertFalse(suggestion.applying(suggestion.proposed, to: Self.standard).weekendEnabled)
    }

    /// Окремий розклад уже є — кожна група проти свого; будні мають перевагу.
    func testSeparateWeekendScheduleIsJudgedOnItsOwn() throws {
        var week = Self.standard
        week.weekendEnabled = true

        // Вихідні о 09:00 — за їхнім розкладом, зсуву немає.
        XCTAssertNil(suggest(window(weekdays: (490, 1250), weekends: (545, 1330)), week))

        let weekendShift = try XCTUnwrap(suggest(window(weekdays: (490, 1250), weekends: (660, 1330)), week))
        XCTAssertEqual(weekendShift.scope, .weekends)
        XCTAssertEqual(weekendShift.current, DaySchedule(wakeMinutes: 540, sleepMinutes: 1380))
        XCTAssertEqual(weekendShift.proposed, DaySchedule(wakeMinutes: 660, sleepMinutes: 1380))

        let both = try XCTUnwrap(suggest(window(weekdays: (390, 1250), weekends: (660, 1330)), week))
        XCTAssertEqual(both.scope, .weekdays)
        let applied = both.applying(both.proposed, to: week)
        XCTAssertEqual(applied.weekday.wakeMinutes, 390)
        XCTAssertEqual(applied.weekend, week.weekend)
    }

    // MARK: - Дані

    /// 7 днів із порціями — і перший тиждень користування: вікна немає. 8 — є.
    func testTooFewActiveDays() {
        let firstWeek: [(first: Int, last: Int)?] = Array(repeating: nil, count: 7) + Array(repeating: (390, 1250), count: 7)
        XCTAssertNil(suggest(window(firstWeek)))
        let eightDays: [(first: Int, last: Int)?] = Array(repeating: nil, count: 6) + Array(repeating: (390, 1250), count: 8)
        XCTAssertNotNil(suggest(window(eightDays)))
    }

    /// Порція о 00:30 — ще вчорашній вечір, а не ранній підйом; день лише з нею — без доказів.
    func testPortionsBeforeFourAreLastNight() {
        let days = (0..<14).map { index in
            ScheduleDay(isWeekend: Self.weekendIndices.contains(index), intakeMinutes: [30, 490, 780, 1250])
        }
        XCTAssertNil(suggest(days))

        let nightsOnly = (0..<14).map { ScheduleDay(isWeekend: Self.weekendIndices.contains($0), intakeMinutes: [30]) }
        XCTAssertNil(suggest(nightsOnly), "ні ранку, ні вечора — порції лише до 04:00")
    }

    /// Медіана — до найближчих 15 хв.
    func testRoundsToQuarterHour() throws {
        XCTAssertEqual(try XCTUnwrap(suggest(window(weekdays: (397, 1250), weekends: (397, 1250)))).proposed.wakeMinutes, 390)
        XCTAssertEqual(try XCTUnwrap(suggest(window(weekdays: (413, 1250), weekends: (413, 1250)))).proposed.wakeMinutes, 420)
        XCTAssertEqual(ScheduleShift.median([1, 4, 2, 3]), 2.5)
    }

    /// Межі екрана «Сповіщення»: відбій не пізніше 24:00, активних годин ≥ 6.
    func testProposalStaysWithinSettingsBounds() throws {
        let midnight = try XCTUnwrap(suggest(window(weekdays: (490, 1436), weekends: (490, 1439))))
        XCTAssertEqual(midnight.proposed.sleepMinutes, 1440)

        // Перша склянка о 17:30 при відбої 22:00 — відбій поступається до 23:30.
        let lateDay = try XCTUnwrap(suggest(window(weekdays: (1050, 1300), weekends: (1050, 1300))))
        XCTAssertEqual(lateDay.proposed, DaySchedule(wakeMinutes: 1050, sleepMinutes: 1410))
    }

    // MARK: - Частота показу

    func testOfferPolicy() {
        func can(_ outcome: ScheduleOfferOutcome, days: Int?, shift: Int = 90, answered: Int = 90) -> Bool {
            ScheduleOfferPolicy.canOffer(shift: shift, last: outcome, daysSinceShown: days, answeredShift: answered)
        }
        XCTAssertTrue(can(.none, days: nil), "ще не показували")

        XCTAssertFalse(can(.dismissed, days: 6))
        XCTAssertTrue(can(.dismissed, days: 7), "закрили без відповіді — через 7 днів")

        XCTAssertFalse(can(.accepted, days: 29))
        XCTAssertTrue(can(.accepted, days: 30), "не частіше ніж раз на 30 днів")

        XCTAssertFalse(can(.declined, days: 59))
        XCTAssertTrue(can(.declined, days: 60), "«Ні» — 60 днів")
        XCTAssertFalse(can(.declined, days: 45, shift: 149), "зсув виріс менше ніж на 60 хв")
        XCTAssertTrue(can(.declined, days: 45, shift: 150), "зсув виріс на 60 хв — можна раніше")
        XCTAssertFalse(can(.declined, days: 29, shift: 300), "але не частіше ніж раз на 30 днів")
    }
}

/// Те саме з бази: 14 повних днів до сьогодні, видалені порції не рахуються.
@MainActor
final class ScheduleSuggestionServiceTests: XCTestCase {
    private var dayLogs: DayLogRepository!
    private var profiles: ProfileRepository!
    private var insights: InsightsService!
    private var calendar: CalendarService!
    private var container: ModelContainer!

    override func setUp() async throws {
        container = Database.makeInMemoryContainer()
        let context = container.mainContext
        let clock = FixedClock(now: Self.date("2026-10-05", 12))
        calendar = CalendarService(clock: clock)
        dayLogs = DayLogRepository(context: context)
        profiles = ProfileRepository(context: context)
        let metrics = MetricsService(store: MetricStore(context: context), calendar: calendar)
        insights = InsightsService(dayLogs: dayLogs, profiles: profiles, metrics: metrics, calendar: calendar)
    }

    private static func date(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let key = DayKey(rawValue: day)
        return calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day, hour: hour, minute: minute))!
    }

    @discardableResult
    private func drink(_ day: String, _ hour: Int, _ minute: Int) -> Intake {
        let log = dayLogs.dayLog(for: DayKey(rawValue: day), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        let intake = Intake(amountMl: 250, createdAt: Self.date(day, hour, minute))
        dayLogs.insert(intake, into: log)
        log.entriesCount += 1
        dayLogs.save()
        return intake
    }

    private func earlyDays(_ range: ClosedRange<Int>, month: String = "2026-09") {
        for day in range {
            let key = "\(month)-\(String(format: "%02d", day))"
            drink(key, 6, 30)
            drink(key, 13, 0)
            drink(key, 21, 0)
        }
    }

    /// Вікно — рівно 14 повних днів: 21.09 (сьогодні − 14) … 04.10.
    func testReadsFourteenFullDaysBeforeToday() throws {
        earlyDays(21...28)
        let suggestion = try XCTUnwrap(insights.scheduleSuggestion())
        XCTAssertEqual(suggestion.proposed.wakeMinutes, 390)
    }

    /// 13–20 вересня — уже поза вікном, а сьогоднішній день ще не закінчився.
    func testTodayAndOlderDaysAreOutsideTheWindow() {
        earlyDays(13...20)
        for _ in 0..<3 { drink("2026-10-05", 6, 30) }
        XCTAssertNil(insights.scheduleSuggestion())
    }

    /// Ранні порції трьох днів видалено — лишилось 6 ранніх із 9, це менше за 70 %.
    func testDeletedIntakesDoNotCount() {
        earlyDays(22...30)
        XCTAssertNotNil(insights.scheduleSuggestion())
        for day in 22...24 {
            dayLogs.activeIntakes(for: DayKey(rawValue: "2026-09-\(day)"))
                .filter { calendar.minuteOfDay($0.createdAt) == 390 }
                .forEach { $0.deletedAt = Self.date("2026-10-01", 9) }
        }
        dayLogs.save()
        XCTAssertNil(insights.scheduleSuggestion())
    }
}
