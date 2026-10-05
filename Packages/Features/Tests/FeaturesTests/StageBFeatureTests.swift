import XCTest
import SwiftData
import Core
import Persistence
import Insights
import Gamification
import Notifications
@testable import Features

/// Сповіщення, етап B у композиційному корені (WAT-37): вікно «Склянка», звіт-історія, налаштування.
@MainActor
final class StageBFeatureTests: XCTestCase {
    private var clock: FixedClock!
    private var services: AppServices!

    /// 1 жовтня 2026 (четвер), за Києвом.
    private static func date(day: Int = 1, _ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: parts)!
    }

    override func setUp() async throws {
        try await super.setUp()
        clock = FixedClock(now: Self.date(21))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock,
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    // MARK: - Вікно «Склянка» (§7.1)

    func testMorningTapOpensGlassWindow() async {
        services.simulateNotificationTap(.morning)
        XCTAssertEqual(services.router.takePath(), [])
        XCTAssertEqual(services.router.takeHomeIntent(), .glass)

        await services.handleNotificationResponse(NotificationResponseInfo(
            identifier: "wt.morning.2026-10-01", action: .open, userInfo: [UserInfoKey.route: "glass"]))
        XCTAssertEqual(services.router.takeHomeIntent(), .glass)
    }

    /// Перше відкриття питає «скільки в твоїй склянці?», далі — одразу склянка.
    func testCalibrationIsAskedOnce() {
        let model = HomeViewModel(services: services)
        model.apply(.glass)
        XCTAssertEqual(model.sheet, .glass)
        XCTAssertEqual(model.glassStage, .calibrate)

        model.calibrationChoice = 300
        model.confirmCalibration()
        XCTAssertEqual(services.profile.glassMl, 300)
        XCTAssertTrue(services.profile.glassConfirmed)
        XCTAssertEqual(model.glassStage, .pour)
        XCTAssertEqual(model.glassAmount, 300, "за замовчуванням — повна склянка")

        model.dismissSheet()
        model.apply(.glass)
        XCTAssertEqual(model.glassStage, .pour)
    }

    /// Чип, що дав би менше за 50 мл, прихований: при склянці < 200 мл зникає «¼» (§7.1, п. 2).
    func testTinyFractionChipIsHidden() {
        let model = HomeViewModel(services: services)
        services.profile.glassMl = 250
        XCTAssertEqual(model.glassFractions.map(\.title), ["Повна", "¾", "½", "¼"])
        XCTAssertEqual(model.glassMl(for: 0.5), 125)
        services.profile.glassMl = 150
        XCTAssertEqual(model.glassFractions.map(\.title), ["Повна", "¾", "½"])
    }

    func testFractionWordAndAccessibilityValue() {
        let model = HomeViewModel(services: services)
        services.profile.glassMl = 250
        model.selectGlassFraction(0.75)
        XCTAssertEqual(model.glassFractionWord, "три чверті")
        model.glassAmount = 175
        XCTAssertNil(model.glassFractionWord)
        XCTAssertEqual(model.glassAccessibilityValue, "175 мл")
    }

    func testRecordingAddsIntake() {
        let model = HomeViewModel(services: services)
        services.profile.glassConfirmed = true
        model.apply(.glass)
        model.glassAmount = 225
        model.confirmGlass()
        XCTAssertEqual(services.dayLogs.activeIntakes(for: services.calendar.today).map(\.amountMl), [225])
        XCTAssertEqual(model.glassRecorded, 225, "«+225» на мить, потім вікно закривається саме")
    }

    /// Склянку задали в налаштуваннях — вікно вже не питає (§7.1, п. 5).
    func testGlassStepperConfirmsGlass() {
        let settings = NotificationsSettingsModel(services: services)
        settings.stepGlass(1)
        XCTAssertEqual(services.profile.glassMl, 275)
        XCTAssertTrue(services.profile.glassConfirmed)
    }

    // MARK: - Звіт (§11)

    func testReportTapRoutes() async {
        await services.handleNotificationResponse(NotificationResponseInfo(
            identifier: "wt.report.2026-10-05.weekmonth", action: .open,
            userInfo: [UserInfoKey.route: "report:week:2026-09-28,month:2026-09"]))
        XCTAssertEqual(services.router.takePath(),
                       [.report([.week(start: DayKey(rawValue: "2026-09-28")), .month(MonthKey(rawValue: "2026-09"))])])

        services.simulateNotificationTap(.report)
        XCTAssertEqual(services.router.takePath(), [.report([.week(start: DayKey(rawValue: "2026-09-21"))])],
                       "демо-тап — минулий тиждень")
    }

    /// Контекст планувальника несе числа денного звіту — сповіщення формулює їх саме (§11.2).
    func testContextCarriesDailyDigest() {
        services.hydration.addIntake(amountMl: 700, at: Self.date(9))
        let digest = services.makeNotificationContext().reports.first { $0.period == .day(services.calendar.today) }
        XCTAssertEqual(digest?.hasIntakes, true)
        XCTAssertEqual(digest?.totalMl, 700)
        XCTAssertEqual(digest?.weakestPart, "день", "без порцій після 12:00 — 0 % від потрібного")
    }

    func testDayReportSlides() {
        services.hydration.addIntake(amountMl: 300, at: Self.date(8, 30))
        services.hydration.addIntake(amountMl: 400, at: Self.date(10))
        let presenter = presenter(for: .day(services.calendar.today), nowMinute: 21 * 60)

        XCTAssertEqual(presenter.header, "1 ЖОВТНЯ · ЧЕТВЕР")
        XCTAssertEqual(presenter.previousTitle, "‹ Учора")
        let slides = presenter.slides
        XCTAssertEqual(slides.count, 4)
        guard case let .timeline(_, title, blocks, drops, _, rows, foot) = slides[1] else { return XCTFail("\(slides[1])") }
        XCTAssertEqual(title, "2 порції — і 1 з 3 частин дня закрито")
        XCTAssertEqual(blocks.map(\.reached), [true, false, false])
        XCTAssertEqual(blocks.first?.label, "✓ +10 XP")
        XCTAssertEqual(drops.count, 2)
        XCTAssertEqual(rows.map(\.title), ["08:00–12:00", "12:00–17:00", "17:00–22:00"])
        XCTAssertEqual(foot, "Найслабше — день: 0 % від потрібного")
        guard case let .thought(_, emoji, headline, detail, _) = slides[3] else { return XCTFail("\(slides[3])") }
        XCTAssertEqual(emoji, "🌙")
        XCTAssertEqual(headline, "Ранок і полудень — найсильніша частина: 102 % від потрібного")
        XCTAssertEqual(detail, "Добраніч. Завтра ранкова склянка — о 08:00.")
    }

    /// Посеред сьогоднішнього дня частини, що ще попереду, «найслабшими» не стають.
    func testTodayMidDayDoesNotJudgeFutureParts() {
        services.hydration.addIntake(amountMl: 300, at: Self.date(8, 30))
        let slides = presenter(for: .day(services.calendar.today), nowMinute: 11 * 60).slides
        guard case let .timeline(_, _, _, _, _, _, foot) = slides[1] else { return XCTFail() }
        XCTAssertNil(foot)
    }

    func testWeekHeaderAcrossMonthsAndEmptyPeriod() {
        let week = presenter(for: .week(start: DayKey(rawValue: "2026-09-28")), nowMinute: nil)
        XCTAssertEqual(week.header, "28 ВЕРЕСНЯ – 4 ЖОВТНЯ")
        guard case .empty = week.slides.first else { return XCTFail("без порцій — один слайд") }
        XCTAssertEqual(week.slides.count, 1)

        let month = presenter(for: .month(MonthKey(rawValue: "2026-09")), nowMinute: nil)
        XCTAssertEqual(month.header, "ВЕРЕСЕНЬ 2026")
        XCTAssertEqual(month.previousTitle, "‹ Серпень")
    }

    func testFormatting() {
        XCTAssertEqual(ReportFormat.volume(850), "850 мл")
        XCTAssertEqual(ReportFormat.volume(1850), "1,9 л")
        XCTAssertEqual(ReportFormat.volume(52_000), "52 л")
        XCTAssertEqual(ReportFormat.big(250).unit, "мл")
        XCTAssertEqual(ReportFormat.big(13_300).value, 13.3)
        XCTAssertEqual(ReportFormat.big(13_300).decimals, 1)
    }

    private func presenter(for period: ReportPeriod, nowMinute: Int?) -> ReportPresenter {
        let calendar = services.calendar
        let days = calendar.days(in: period)
        return ReportPresenter(
            report: services.insights.report(for: period),
            game: services.gamification.periodSummary(days: days),
            streak: services.gamification.streakSummary(),
            recentGoalDays: Array(repeating: false, count: 7),
            schedule: services.profile.schedule(isWeekend: false),
            weekendScheduleEnabled: false,
            dayPartXp: 10,
            today: calendar.today,
            tomorrowMorning: "08:00",
            nowMinute: nowMinute,
            calendar: calendar
        )
    }
}
