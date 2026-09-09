import XCTest
import SwiftData
import Core
import Persistence
import Metrics
import Hydration
import Gamification
@testable import Features

/// Наскрізні перевірки звʼязки «облік води → метрики → гейміфікація».
/// Це єдине місце, де модулі зустрічаються разом (PLAN.md §2).
@MainActor
final class IntegrationTests: XCTestCase {
    private var services: AppServices!

    override func setUp() async throws {
        try await super.setUp()
        services = AppServices(
            container: Database.makeInMemoryContainer(),
            clock: FixedClock(now: Self.date(day: 18, hour: 10))
        )
        services.bootstrap()
    }

    private static func date(day: Int, hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = day; c.hour = hour
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    func testBootstrapCreatesDefaultState() {
        XCTAssertEqual(services.hydration.currentGoal(), 2000)
        XCTAssertEqual(services.hydration.quickAddAmounts(), [200, 500, 1000])
        XCTAssertEqual(services.gamification.levelProgress().level, 1)
        XCTAssertEqual(services.gamification.dailyQuests().count, 2)
        XCTAssertEqual(services.gamification.achievementSnapshots().count, 7)
    }

    func testAddingWaterDrivesEveryModule() {
        services.hydration.addIntake(amountMl: 500)

        XCTAssertEqual(services.hydration.todaySnapshot().totalMl, 500)
        XCTAssertGreaterThan(services.gamification.levelProgress().totalXp, 0, "нараховано XP")
        XCTAssertTrue(
            services.gamification.achievementSnapshots().first { $0.key == "first.drop" }!.isUnlocked,
            "розблоковано «Першу краплю»"
        )
        XCTAssertEqual(services.gamification.dailyQuests().first { $0.key == "daily.goal" }?.progress, 500)
        XCTAssertEqual(services.insights.evenness().totalMl, 500)
    }

    func testUndoRollsBackEveryModule() {
        let result = services.hydration.addIntake(amountMl: 500)!
        let xpAfterAdd = services.gamification.levelProgress().totalXp

        services.hydration.removeIntake(id: result.intakeId)

        XCTAssertEqual(services.hydration.todaySnapshot().totalMl, 0)
        XCTAssertLessThan(services.gamification.levelProgress().totalXp, xpAfterAdd)
        XCTAssertFalse(
            services.gamification.achievementSnapshots().first { $0.key == "first.drop" }!.isUnlocked
        )
        XCTAssertEqual(services.gamification.dailyQuests().first { $0.key == "daily.goal" }?.progress, 0)
    }

    /// Тост «Скасувати» веде сюди: відкат відкату має повернути стан усіх модулів,
    /// а не лише число на кільці.
    func testRestoreRollsForwardEveryModule() {
        let result = services.hydration.addIntake(amountMl: 500)!
        let xpAfterAdd = services.gamification.levelProgress().totalXp
        let questAfterAdd = services.gamification.dailyQuests().first { $0.key == "daily.goal" }?.progress

        services.hydration.removeIntake(id: result.intakeId)
        services.hydration.restoreIntake(id: result.intakeId)

        XCTAssertEqual(services.hydration.todaySnapshot().totalMl, 500)
        XCTAssertEqual(services.gamification.levelProgress().totalXp, xpAfterAdd, "XP повернувся рівно один раз")
        XCTAssertTrue(
            services.gamification.achievementSnapshots().first { $0.key == "first.drop" }!.isUnlocked,
            "досягнення розблокувалось повторно"
        )
        XCTAssertEqual(services.gamification.dailyQuests().first { $0.key == "daily.goal" }?.progress, questAfterAdd)
        XCTAssertEqual(services.insights.evenness().totalMl, 500)
    }

    /// Повний цикл через модель екрана — саме так це робить кнопка «Скасувати».
    func testHomeViewModelUndoRestoresHistoryAndProgress() {
        let model = HomeViewModel(services: services)
        model.add(500)
        let pctAfterAdd = model.day.completionPct

        let intakeId = model.history[0].id
        model.remove(id: intakeId)
        XCTAssertEqual(model.day.completionPct, 0)
        XCTAssertEqual(model.toast?.restoreIntakeId, intakeId, "тост пропонує скасування")

        model.undoToast()

        XCTAssertEqual(model.day.completionPct, pctAfterAdd)
        XCTAssertEqual(model.history.count, 1, "порція повернулась в історію")
    }

    /// Закриття норми має відгукнутися окремим пульсом, а не звичайним «додано».
    /// Норма й новий рівень часто закриваються тією самою порцією — тоді виграє рівень,
    /// бо це рідша подія, і до неї додається тост.
    func testClosingGoalRaisesItsOwnPulse() {
        let model = HomeViewModel(services: services)
        for _ in 0..<3 { model.add(500) }
        XCTAssertEqual(model.pulse?.kind, .added(500), "норма ще не закрита")
        XCTAssertNil(model.toast)

        model.add(500)
        if case .levelUp = model.pulse?.kind {
            XCTAssertNotNil(model.toast, "разом з нормою піднявся рівень — має бути тост")
        } else {
            XCTAssertEqual(model.pulse?.kind, .goalReached, "четверта порція закрила норму")
        }

        model.add(500)
        XCTAssertNotEqual(model.pulse?.kind, .goalReached, "повторно норму не «закривають»")
    }

    func testCappedNoteAppearsOnlyAboveCeiling() {
        let model = HomeViewModel(services: services)
        for _ in 0..<4 { model.add(500) }
        XCTAssertNil(model.cappedNote, "рівно 100 % — стелі ще немає")

        for _ in 0..<2 { model.add(500) }
        XCTAssertEqual(model.day.completionPct, 120)
        XCTAssertNotNil(model.cappedNote, "понад 120 % — пояснюємо, чому відсоток стоїть")
    }

    func testClosingDailyGoalBuildsStreakAndInsights() {
        for _ in 0..<4 { services.hydration.addIntake(amountMl: 500) }

        XCTAssertTrue(services.hydration.todaySnapshot().goalMet)
        XCTAssertEqual(services.gamification.streakSummary().current, 1)
        XCTAssertTrue(services.gamification.dailyQuests().first { $0.key == "daily.goal" }!.isDone)
        XCTAssertGreaterThan(services.insights.evenness().score, 0)
    }

    /// WAT-11: крапки в шапці — фіксований тиждень Пн…Нд, а не останні 7 діб.
    /// Позиція крапки задана днем тижня, тому тиждень заповнюється зліва направо,
    /// а сьогоднішня крапка стоїть крайньою правою лише в неділю.
    func testWeekDotsFollowCalendarWeek() {
        let model = HomeViewModel(services: services)
        XCTAssertEqual(model.weekDots, Array(repeating: false, count: 7), "порожній тиждень")

        for _ in 0..<4 { model.add(500) }
        // 18 липня 2026 — субота: 6-та позиція, а праворуч лишається порожня неділя.
        XCTAssertEqual(model.weekDots, [false, false, false, false, false, true, false])

        for _ in 0..<4 { services.hydration.addIntake(amountMl: 500, at: Self.date(day: 15, hour: 12)) }
        model.reload()
        // Середа 15 липня стає 3-ю позицією — ліворуч від суботи, а не поруч із нею.
        XCTAssertEqual(model.weekDots, [false, false, true, false, false, true, false])
    }

    func testFixtureSeederProducesUsableHistory() {
        FixtureSeeder.seed(into: services, days: 20)

        XCTAssertGreaterThan(services.insights.volumeChart(mode: .days7).bars.filter { $0.ml > 0 }.count, 3)
        XCTAssertFalse(services.insights.typicalDay(period: .week7).rows.isEmpty)
        XCTAssertTrue(services.insights.calendar(month: services.calendar.currentMonth).hasData)
        XCTAssertGreaterThan(services.gamification.levelProgress().level, 1)
        XCTAssertFalse(services.gamification.prizes().isEmpty, "рівні видали призи")
    }

    func testHeatmapReflectsDrinkingHours() {
        services.hydration.addIntake(amountMl: 300, at: Self.date(day: 18, hour: 8))
        services.hydration.addIntake(amountMl: 300, at: Self.date(day: 18, hour: 8))
        services.hydration.addIntake(amountMl: 200, at: Self.date(day: 18, hour: 20))

        let report = services.insights.heatmap(period: .week7)
        let saturdayRow = report.rows[5] // 18 липня 2026 — субота
        let morning = saturdayRow.first { $0.hourBucket == 8 }!
        let evening = saturdayRow.first { $0.hourBucket == 20 }!

        XCTAssertEqual(morning.ml, 600)
        XCTAssertEqual(evening.ml, 200)
        XCTAssertGreaterThan(morning.level, evening.level)
    }
}
