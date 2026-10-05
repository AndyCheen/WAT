import XCTest
import SwiftData
import Core
import Persistence
import Metrics
@testable import Insights

/// Звіти — SPEC-NOTIFICATIONS §11. «Сьогодні» — понеділок 5 жовтня 2026, 12:00 за Києвом.
@MainActor
final class ReportsTests: XCTestCase {
    private var container: ModelContainer!
    private var dayLogs: DayLogRepository!
    private var profiles: ProfileRepository!
    private var insights: InsightsService!
    private var calendar: CalendarService!

    override func setUp() async throws {
        container = Database.makeInMemoryContainer()
        let context = container.mainContext
        let clock = FixedClock(now: Self.date("2026-10-05", 12))
        calendar = CalendarService(clock: clock)
        dayLogs = DayLogRepository(context: context)
        profiles = ProfileRepository(context: context)
        profiles.setGoal(2000, source: .seed, effectiveFrom: DayKey(rawValue: "2020-01-01"), at: clock.now)
        let metrics = MetricsService(store: MetricStore(context: context), calendar: calendar)
        insights = InsightsService(dayLogs: dayLogs, profiles: profiles, metrics: metrics, calendar: calendar)
    }

    private static func date(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let key = DayKey(rawValue: day)
        return calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day, hour: hour, minute: minute))!
    }

    /// Порція з перерахунком денного агрегату — так само, як це робить `HydrationService`.
    private func drink(_ day: String, _ hour: Int, _ minute: Int = 0, _ ml: Int) {
        let key = DayKey(rawValue: day)
        let log = dayLogs.dayLog(for: key, goalMl: 2000, timeZoneId: "Europe/Kyiv")
        log.scheduleSnapshot = profiles.profile().schedule(isWeekend: calendar.isWeekend(key))
        dayLogs.insert(Intake(amountMl: ml, createdAt: Self.date(day, hour, minute)), into: log)
        log.partTotals[DayPart.from(hour: hour).rawValue] += ml
        log.totalMl += ml
        log.countedMl = min(log.totalMl, log.capMl)
        log.entriesCount += 1
        dayLogs.save()
    }

    /// Рівномірний день: по склянці в кожній частині, разом `total`.
    private func evenDay(_ day: String, total: Int = 2000) {
        let shares: [(Int, Double)] = [(9, 0.33), (14, 0.39), (19, 0.28)]
        for (hour, share) in shares { drink(day, hour, 0, Int(Double(total) * share)) }
    }

    // MARK: - Тиждень

    func testWeekTotalsAndComparison() {
        // Минулий тиждень 21–27 вересня: щодня 1500.
        for day in 21...27 { evenDay("2026-09-\(day)", total: 1500) }
        // Звітний 28 вересня – 4 жовтня: 5 днів норми, середа й субота — по 1000.
        for day in ["2026-09-28", "2026-09-29", "2026-10-01", "2026-10-02", "2026-10-04"] { evenDay(day, total: 2000) }
        evenDay("2026-09-30", total: 1000)
        evenDay("2026-10-03", total: 1000)
        drink("2026-10-01", 21, 0, 400)  // четвер — найкращий день

        let report = insights.report(for: .week(start: DayKey(rawValue: "2026-09-28")))
        XCTAssertEqual(report.days.count, 7)
        XCTAssertEqual(report.goalDays, 5)
        XCTAssertEqual(report.totalMl, 12_400)
        XCTAssertEqual(report.averageMl, 1771)
        XCTAssertEqual(report.bestDay?.day.rawValue, "2026-10-01")
        XCTAssertEqual(report.previous?.averageMl, 1500)
        XCTAssertEqual(report.averageChangePercent, 18)
        XCTAssertEqual(report.longestStreak?.length, 2)
        XCTAssertEqual(report.thought, .improvement(percent: 18), "прогалини немає — далі покращення ≥ 10 %")
    }

    // MARK: - День

    func testDayBlocksMatchGoalBlocks() {
        drink("2026-10-04", 8, 30, 300)
        drink("2026-10-04", 10, 0, 420)
        drink("2026-10-04", 13, 0, 520)
        drink("2026-10-04", 18, 0, 560)
        let report = insights.report(for: .day(DayKey(rawValue: "2026-10-04")))

        XCTAssertEqual(report.blocks.map(\.title), ["ранок і полудень", "день", "вечір"])
        XCTAssertEqual(report.blocks.map(\.targetMl), [649, 780, 571])
        XCTAssertEqual(report.blocks.compactMap(\.drunkMl), [720, 520, 560])
        XCTAssertEqual(report.blocks.map(\.isReached), [true, false, false])
        XCTAssertEqual(report.weakestBlock?.title, "день")
        XCTAssertEqual(report.portions.map(\.minute), [510, 600, 780, 1080])
        XCTAssertEqual(report.thought, .strongestPart(title: "ранок і полудень", percent: 111))
    }

    // MARK: - Одна модель частин доби (WAT-39)

    /// Склянка о 06:30 при підйомі о 08:00 разом із порціями до 12:00 закриває «до 12:00».
    func testPortionBeforeWakeClosesFirstBlock() {
        drink("2026-10-04", 6, 30, 250)
        drink("2026-10-04", 9, 0, 200)
        drink("2026-10-04", 11, 0, 200)
        drink("2026-10-04", 22, 30, 300)
        let report = insights.report(for: .day(DayKey(rawValue: "2026-10-04")))
        XCTAssertEqual(report.blocks.compactMap(\.drunkMl), [650, 0, 300], "22:30 — вечору")
        XCTAssertEqual(report.blocks.map(\.isReached), [true, false, false])
    }

    /// Після зміни підйому з 08:00 на 06:00 звіт за минулий день не змінюється: межі — зі знімка дня.
    func testScheduleChangeDoesNotRewritePastDay() {
        drink("2026-10-04", 8, 30, 300)
        drink("2026-10-04", 10, 0, 400)
        let day = ReportPeriod.day(DayKey(rawValue: "2026-10-04"))
        let before = insights.report(for: day)

        profiles.profile().wakeMinutes = 6 * 60
        profiles.save()

        let after = insights.report(for: day)
        XCTAssertEqual(after.blocks, before.blocks)
        XCTAssertEqual(after.schedule, DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60))
        XCTAssertEqual(after.blocks.first?.isReached, true)
        XCTAssertEqual(insights.evenness(for: DayKey(rawValue: "2026-10-04")).rows.map(\.idealMl), [130, 519, 780, 571, 0])
    }

    /// Дні без знімка (історія до WAT-39) — розклад із профілю.
    func testDayWithoutSnapshotFollowsProfile() {
        drink("2026-10-04", 10, 0, 400)
        dayLogs.existingDayLog(for: DayKey(rawValue: "2026-10-04"))?.scheduleSnapshot = nil
        profiles.profile().wakeMinutes = 6 * 60
        profiles.save()

        let report = insights.report(for: .day(DayKey(rawValue: "2026-10-04")))
        XCTAssertEqual(report.schedule.wakeMinutes, 6 * 60)
        XCTAssertEqual(report.blocks.first?.fromMinute, 6 * 60)
    }

    /// «Рівномірність» і звіт рахують той самий день однаково: ранок 130 + полудень 519 = 649
    /// до 12:00, ніч без ризки, сума цілей — норма.
    func testEvennessUsesReportModel() {
        drink("2026-10-04", 8, 30, 300)
        drink("2026-10-04", 13, 0, 520)
        let day = DayKey(rawValue: "2026-10-04")
        let rows = insights.evenness(for: day).rows
        let blocks = insights.report(for: .day(day)).blocks

        XCTAssertEqual(rows.map(\.idealMl), [130, 519, 780, 571, 0])
        XCTAssertEqual(rows.map(\.idealMl).reduce(0, +), 2000)
        XCTAssertEqual(rows[0].idealMl + rows[1].idealMl, blocks[0].targetMl)
        XCTAssertEqual(rows[2].idealMl, blocks[1].targetMl)
        XCTAssertEqual(rows[3].idealMl, blocks[2].targetMl)
        XCTAssertNil(rows[DayPart.night.rawValue].tickFraction, "ніч поза активними годинами — без ризки")
        XCTAssertTrue(rows.dropLast().allSatisfy { $0.tickFraction != nil })
        XCTAssertEqual(insights.dayDetail(for: day)?.rhythm.map(\.idealMl), rows.map(\.idealMl))
    }

    /// «Типова доба»: ризка — частка кривої; ніч без неї.
    func testTypicalDayIdealFromCurve() {
        for day in 1...4 { evenDay("2026-10-0\(day)") }
        let rows = insights.typicalDay(period: .week7).rows
        XCTAssertNil(rows[DayPart.night.rawValue].ideal)
        XCTAssertEqual(rows[DayPart.morning.rawValue].ideal ?? 0, 130.0 / 2000, accuracy: 0.001)
        XCTAssertEqual(rows.compactMap(\.ideal).reduce(0, +), 1, accuracy: 1e-9)
    }

    func testEmptyPeriodHasNoThought() {
        let report = insights.report(for: .day(DayKey(rawValue: "2026-10-04")))
        XCTAssertFalse(report.hasData)
        XCTAssertNil(report.thought)
    }

    // MARK: - Системна прогалина (§10.1)

    func testWeakDayPartFindsSystematicGap() {
        // 10 днів: ранок і день — повністю, вечір — 100 мл із 571.
        for day in 22...30 { forgetfulEvening("2026-09-\(day)") }
        forgetfulEvening("2026-10-01")
        let weak = insights.weakDayPart(days: calendar.recentDays(14, endingAt: DayKey(rawValue: "2026-10-01")))
        XCTAssertEqual(weak?.key, "evening")
        XCTAssertEqual(weak?.title, "вечір")
        XCTAssertEqual(weak?.toMinute, 22 * 60)
        XCTAssertEqual(weak?.median ?? 1, 0.18, accuracy: 0.01)
    }

    func testNoWeakPartWithoutEnoughHistoryOrGap() {
        for day in 22...27 { forgetfulEvening("2026-09-\(day)") }
        XCTAssertNil(insights.weakDayPart(days: calendar.recentDays(14, endingAt: DayKey(rawValue: "2026-09-27"))),
                     "6 активних днів — замало")

        for day in 22...30 { evenDay("2026-09-\(day)") }
        XCTAssertNil(insights.weakDayPart(days: calendar.recentDays(14, endingAt: DayKey(rawValue: "2026-09-30"))))
    }

    /// Прогалина — перше правило думки (§11.4).
    func testWeakPartWinsThoughtPriority() {
        for day in 21...30 { forgetfulEvening("2026-09-\(day)") }
        let report = insights.report(for: .week(start: DayKey(rawValue: "2026-09-28")))
        guard case .weakPart(let weak) = report.thought else { return XCTFail("\(String(describing: report.thought))") }
        XCTAssertEqual(weak.key, "evening")
    }

    private func forgetfulEvening(_ day: String) {
        drink(day, 9, 0, 650)
        drink(day, 14, 0, 780)
        drink(day, 19, 0, 100)
    }

    // MARK: - Будні проти вихідних, найкращий день

    func testWeekendGapThought() {
        for day in 1...30 {
            let key = String(format: "2026-09-%02d", day)
            let weekend = calendar.isWeekend(DayKey(rawValue: key))
            evenDay(key, total: weekend ? 1200 : 2000)
        }
        let report = insights.report(for: .month(MonthKey(rawValue: "2026-09")))
        XCTAssertEqual(report.thought, .weekendGap(percent: 40, weekendLess: true))
        XCTAssertEqual(report.days.count, 30)
    }

    func testBestDayIsTheFallbackThought() {
        evenDay("2026-09-28", total: 1800)
        evenDay("2026-09-29", total: 1900)
        let report = insights.report(for: .week(start: DayKey(rawValue: "2026-09-28")))
        guard case .bestDay(let best) = report.thought else { return XCTFail("\(String(describing: report.thought))") }
        XCTAssertEqual(best.day.rawValue, "2026-09-29")
    }

    /// Поточний місяць: дні після сьогодні — майбутні й у середнє не входять.
    func testCurrentMonthMarksFutureDays() {
        evenDay("2026-10-01", total: 2000)
        let report = insights.report(for: .month(MonthKey(rawValue: "2026-10")))
        XCTAssertEqual(report.days.filter(\.isFuture).count, 26)
        XCTAssertEqual(report.averageMl, 400, "2000 мл за 5 днів, що настали")
    }
}
