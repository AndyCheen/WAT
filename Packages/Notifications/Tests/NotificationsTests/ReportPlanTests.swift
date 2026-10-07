import XCTest
import Core
import Persistence
@testable import Notifications

/// Звіти — SPEC-NOTIFICATIONS §11: денний о відбої тихо, тижневий у понеділок о 10:00, місячний
/// 1-го о 10:00; тиждень і місяць в один день — одне сповіщення.
final class ReportPlanTests: XCTestCase {
    private func day(_ raw: String) -> DayKey { DayKey(rawValue: raw) }

    private func plan(at now: Date, reports: [ReportDigest], lastIntake: Date? = nil,
                      _ preferences: NotificationPreferences = .default) -> [PlannedNotification] {
        var context = Fixture.context(at: now)
        context.reports = reports
        context.lastIntakeAt = lastIntake
        return NotificationPlanner.plan(context: context, preferences: preferences).items.filter { $0.type == .report }
    }

    private func digest(_ period: ReportPeriod, hasIntakes: Bool = true) -> ReportDigest {
        ReportDigest(period: period, hasIntakes: hasIntakes, totalMl: 1800, goalMl: 2000, goalDays: 5, dayCount: 7,
                     averageMl: 1900, averageChangePercent: 8, weakestPart: "вечір", longestStreak: 9, glasses: 208)
    }

    // MARK: - Які періоди потрапляють у горизонт

    func testReportPeriodsInHorizon() {
        // Неділя 4 жовтня: завтра понеділок — тижневий за 28 вересня – 4 жовтня.
        XCTAssertEqual(NotificationPlanner.reportPeriods(now: Fixture.date(day: 4, 7), timeZone: Fixture.kyiv, preferences: .default),
                       [.day(day("2026-10-04")), .week(start: day("2026-09-28"))])
        // 31 травня 2026 — неділя, 1 червня — понеділок і перше число.
        XCTAssertEqual(NotificationPlanner.reportPeriods(now: Fixture.date(day: 31, 7, month: 5), timeZone: Fixture.kyiv,
                                                         preferences: .default),
                       [.day(day("2026-05-31")), .week(start: day("2026-05-25")), .month(MonthKey(rawValue: "2026-05"))])
    }

    // MARK: - Денний

    func testDailyReportIsQuietAtBedtime() {
        let report = plan(at: Fixture.date(9), reports: [digest(.day(day("2026-10-01")))]).first
        XCTAssertEqual(report?.id, "wt.report.2026-10-01.day")
        XCTAssertEqual(report.map { Fixture.clock($0.fireAt) }, "22:00")
        XCTAssertEqual(report?.interruption, .passive)
        XCTAssertEqual(report?.isSilent, true)
        XCTAssertNil(report?.category, "без дій — лише тап")
        XCTAssertEqual(report?.tapRoute, .report([.day(day("2026-10-01"))]))
        XCTAssertEqual(report?.title, "Підсумок дня")
    }

    /// «Ти випив 0 л» — докір, а не звіт (§11.1).
    func testNoReportWithoutIntakes() {
        XCTAssertTrue(plan(at: Fixture.date(9), reports: [digest(.day(day("2026-10-01")), hasIntakes: false)]).isEmpty)
    }

    func testDailyReportToggle() {
        var preferences = NotificationPreferences.default
        preferences.dailyReportEnabled = false
        XCTAssertTrue(plan(at: Fixture.date(9), reports: [digest(.day(day("2026-10-01")))], preferences).isEmpty)
    }

    // MARK: - Тиждень і місяць

    /// Свій час 11:00 — подалі від нагадувань понеділка без порцій (09:37, 10:07, 12:07).
    func testWeeklyReportOnMonday() {
        var preferences = NotificationPreferences.default
        preferences.weeklyReportMinutes = 11 * 60
        let report = plan(at: Fixture.date(day: 4, 7), reports: [digest(.week(start: day("2026-09-28")))], preferences).first
        XCTAssertEqual(report?.id, "wt.report.2026-10-05.week")
        XCTAssertEqual(report.map { Fixture.clock($0.fireAt) }, "11:00")
        XCTAssertEqual(report?.interruption, .active)
        XCTAssertEqual(report?.isSilent, true)
        XCTAssertEqual(report?.title, "Тиждень: 5 з 7 днів норми")
        XCTAssertEqual(report?.body, "У середньому 1,9 л на день — на 8 % більше, ніж минулого тижня")
    }

    func testWeekAndMonthMergeOnTheFirstMonday() {
        let week = ReportPeriod.week(start: day("2026-05-25")), month = ReportPeriod.month(MonthKey(rawValue: "2026-05"))
        let reports = plan(at: Fixture.date(day: 31, 7, month: 5), reports: [digest(week), digest(month)])
            .filter { $0.dayKey == day("2026-06-01") }
        XCTAssertEqual(reports.map(\.id), ["wt.report.2026-06-01.weekmonth"])
        XCTAssertEqual(reports.first?.tapRoute, .report([week, month]))
        XCTAssertEqual(reports.first?.title, "Підсумки тижня й місяця")
        XCTAssertEqual(reports.first?.body, "Тиждень: 5 з 7 днів норми · травень: 5 днів норми")
    }

    /// Звіт не конкурує за увагу, але й не стає поруч: зсувається на +30 від будь-якого.
    /// Понеділок без порцій: нагадування 09:37 і 10:07 — звіт 10:00 переїжджає на 10:37.
    func testReportMovesAwayFromActiveNotifications() {
        let report = plan(at: Fixture.date(day: 5, 7), reports: [digest(.week(start: day("2026-09-28")))])
            .first { $0.dayKey == day("2026-10-05") }
        XCTAssertEqual(report.map { Fixture.clock($0.fireAt) }, "10:37")
    }

    /// +2 дні без дій — лише ранкова склянка, звітів теж немає (§13.5, критерій §19.15).
    func testNoReportsAfterTwoInactiveDays() {
        let reports = plan(at: Fixture.date(day: 4, 7), reports: [digest(.day(day("2026-10-04"))),
                                                                   digest(.week(start: day("2026-09-28")))],
                           lastIntake: Fixture.date(day: 2, 12))
        XCTAssertTrue(reports.isEmpty, reports.map(\.id).joined(separator: ", "))
    }

    // MARK: - Ліміт і запит

    func testReportsDoNotCountTowardsDailyCap() {
        func candidate(_ type: NotificationType, _ priority: NotificationPriority, _ hour: Int) -> Candidate {
            Candidate(item: PlannedNotification(id: "\(type.key)\(hour)", type: type, slot: "", dayKey: day("2026-10-01"),
                                                fireAt: Fixture.date(hour), isFloating: false, priority: priority,
                                                category: nil, tapRoute: .home),
                      copy: .morning, rel: 0)
        }
        let active = (8..<16).map { candidate(.reminder, .reminderPrimary, $0) }
        let kept = DailyCap.apply(active + [candidate(.report, .report, 22)], shownCount: 0, cap: 8)
        XCTAssertEqual(kept.count, 9)
    }

    func testPassiveReportRequestIsSilent() {
        var context = Fixture.context(at: Fixture.date(9))
        context.reports = [digest(.day(day("2026-10-01")))]
        let plan = NotificationPlanner.plan(context: context, preferences: .default)
        let request = NotificationScheduler.requests(for: plan, sound: .systemDefault, calendar: Calendar.current)
            .first { $0.identifier == "wt.report.2026-10-01.day" }
        XCTAssertEqual(request?.interruption, .passive)
        XCTAssertEqual(request?.sound, NotificationSoundSpec.none)
        XCTAssertEqual(request?.userInfo[UserInfoKey.route], "report:day:2026-10-01")
    }

    func testTapRouteEncodingRoundTrip() {
        let route = NotificationTapRoute.report([.week(start: day("2026-05-25")), .month(MonthKey(rawValue: "2026-05"))])
        XCTAssertEqual(NotificationTapRoute(encoded: route.encoded), route)
        XCTAssertEqual(NotificationTapRoute(encoded: "glass"), .glass)
    }

    // MARK: - Тексти §11.2

    func testBodiesMatchSpecExamples() {
        XCTAssertEqual(ReportText.day(digest(.day(day("2026-10-01"))), streak: 12),
                       "1,8 л з 2 л (90 %) · серія 12 днів · найслабше — вечір")
        var month = digest(.month(MonthKey(rawValue: "2026-09")))
        month.totalMl = 52_000
        XCTAssertEqual(ReportText.month(month), "52 л за місяць — це 208 склянок · найдовша серія 9 днів")
        XCTAssertEqual(ReportText.monthName(month.period), "Вересень")
    }

    /// Найгірші числа — усе ще ≤ 100 символів: зайві деталі відкидаються, рядок не обрізається.
    func testBodiesFitLockScreenOnWorstNumbers() {
        let worst = ReportDigest(period: .month(MonthKey(rawValue: "2026-11")), hasIntakes: true, totalMl: 155_550,
                                 goalMl: 5000, goalDays: 30, dayCount: 7, averageMl: 5180, averageChangePercent: -100,
                                 weakestPart: "ранок, полудень і день", longestStreak: 365, glasses: 1555)
        for body in [ReportText.day(worst, streak: 1234), ReportText.week(worst), ReportText.month(worst),
                     ReportText.weekMonth(week: worst, month: worst)] {
            XCTAssertLessThanOrEqual(body.count, 100, body)
        }
        for unit in [VolumeUnit.usFluidOunces, .imperialFluidOunces] {
            for body in [ReportText.day(worst, streak: 1234, unit: unit), ReportText.week(worst, unit: unit),
                         ReportText.month(worst, unit: unit)] {
                XCTAssertLessThanOrEqual(body.count, 100, body)
            }
        }
        XCTAssertEqual(ReportText.month(worst, unit: .usFluidOunces).prefix(19), "5260 oz за місяць —")
    }
}
