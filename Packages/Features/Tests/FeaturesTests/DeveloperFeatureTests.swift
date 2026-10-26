import XCTest
import SwiftData
import Core
import Persistence
import Hydration
import Gamification
@testable import Features

/// Режим розробника (WAT-68) на рівні `AppServices`: дії з днями, годинник, скидання, тексти.
@MainActor
final class DeveloperFeatureTests: XCTestCase {
    private var services: AppServices!
    private var clock: OffsetClock!
    private var defaults: UserDefaults!

    private static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = day; c.hour = hour; c.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: UUID().uuidString)
        DeveloperSettings.defaults = defaults
        clock = OffsetClock(base: FixedClock(now: Self.date(day: 26, hour: 14)))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock)
        services.bootstrap()
    }

    override func tearDown() async throws {
        DeveloperSettings.defaults = .standard
        try await super.tearDown()
    }

    private func day(_ number: Int) -> DayKey { DayKey(rawValue: String(format: "2026-10-%02d", number)) }

    // MARK: - Дні

    func testIntakeAtExactTimeOnPastDay() {
        XCTAssertTrue(services.developerAddIntake(ml: 314, day: day(20), minute: 11 * 60 + 11))

        let past = services.developerDay(day(20))
        XCTAssertEqual(past.snapshot.totalMl, 314)
        XCTAssertEqual(past.intakes.first?.timeLabel, "11:11")
        XCTAssertFalse(past.isToday)
    }

    func testTodayRefusesIntakeFromTheFuture() {
        XCTAssertFalse(services.developerAddIntake(ml: 250, day: day(26), minute: 15 * 60))
        XCTAssertTrue(services.developerAddIntake(ml: 250, day: day(26), minute: 13 * 60))
        XCTAssertEqual(services.hydration.todaySnapshot().totalMl, 250)
    }

    func testFillReplacesPortionsWithShareOfTheGoal() {
        services.developerAddIntake(ml: 1000, day: day(20), minute: 9 * 60)

        services.developerFill(day: day(20), percent: 100)
        XCTAssertTrue(services.developerDay(day(20)).snapshot.goalMet)
        XCTAssertEqual(services.developerDay(day(20)).snapshot.totalMl, 2000, "старі порції замінено, а не додано")

        services.developerFill(day: day(20), percent: 0)
        XCTAssertTrue(services.developerDay(day(20)).intakes.isEmpty)
    }

    func testClosedDaysBuildTheStreak() async {
        var reported: [Double] = []
        await services.developerCloseDays(5) { reported.append($0) }

        XCTAssertEqual(services.gamification.streakSummary().current, 5)
        XCTAssertEqual(reported.count, 5, "поступ — після кожного дня")
        XCTAssertEqual(reported.last, 1)
    }

    func testStepwiseDemoMatchesTheSeederAtOnce() async {
        let reference = AppServices(container: Database.makeInMemoryContainer(),
                                    clock: FixedClock(now: Self.date(day: 26, hour: 14)))
        reference.bootstrap()
        // Дозвіл сповіщень приходить асинхронно, а від нього — «На крок попереду»: паузи покрокового заповнення дають
        // йому прийти, тож обидва прогони — з уже відомим дозволом.
        await reference.notifications.refreshAuthorization()
        await services.notifications.refreshAuthorization()
        FixtureSeeder.seed(into: reference)

        await services.developerSeedDemo()

        XCTAssertEqual(services.gamification.levelProgress(), reference.gamification.levelProgress(),
                       "кроками — те саме, що одним пакетом на старті e2e")
        XCTAssertEqual(services.gamification.streakSummary(), reference.gamification.streakSummary())
    }

    func testPastDayGoalReopensTheDay() {
        services.developerFill(day: day(20), percent: 100)
        services.developerSetGoal(2500, day: day(20))

        XCTAssertFalse(services.developerDay(day(20)).snapshot.goalMet)
        XCTAssertEqual(services.hydration.currentGoal(), 2000, "сьогоднішня норма та сама")
    }

    // MARK: - Гра

    func testUnlockShowsCelebrationWindow() {
        services.developerUnlock(achievement: "big.gulp")
        XCTAssertEqual(services.celebration?.keys, ["big.gulp"])
    }

    func testSetLevelMovesCelebratedLevelWithIt() {
        services.developerSetLevel(8)
        XCTAssertEqual(services.gamification.levelProgress().level, 8)
        XCTAssertEqual(services.profile.highestCelebratedLevel, 8, "рівень з режиму розробника не святкується")

        services.developerSetLevel(3)
        XCTAssertEqual(services.profile.highestCelebratedLevel, 3,
                       "униз — і відсвятковане теж: справжнє підняття на 4 отримає тост")
    }

    // MARK: - Годинник

    func testClockShiftStartsNewDayAndPersists() {
        let epoch = services.epoch
        services.developerShiftClock(by: 24 * 3600)

        XCTAssertEqual(services.calendar.today, day(27))
        XCTAssertGreaterThan(services.epoch, epoch, "екрани перечитують себе")
        XCTAssertEqual(DeveloperSettings.clockOffset, 24 * 3600)

        services.developerResetClock()
        XCTAssertEqual(services.calendar.today, day(26))
        XCTAssertEqual(DeveloperSettings.clockOffset, 0)
    }

    // MARK: - Скидання

    func testPendingResetErasesOnceOnNextLaunch() throws {
        let container = Database.makeInMemoryContainer()
        let next = AppServices(container: container, clock: FixedClock(now: Self.date(day: 26, hour: 14)))
        next.bootstrap()
        next.hydration.addIntake(amountMl: 500)
        DeveloperSettings.pendingReset = .progress

        DeveloperSettings.applyPendingReset(to: container)

        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Intake>()), 0)
        XCTAssertNil(DeveloperSettings.pendingReset, "друге відкриття нічого не стирає")
    }

    // MARK: - Тексти

    func testClockOffsetLabels() {
        XCTAssertEqual(DeveloperPresenter.clockOffset(0), "без зсуву")
        XCTAssertEqual(DeveloperPresenter.clockOffset(27 * 3600), "+1 д 3 год")
        XCTAssertEqual(DeveloperPresenter.clockOffset(-45 * 60), "−45 хв")
    }

    func testDayLabels() {
        XCTAssertEqual(DeveloperPresenter.day(day(26)), "Пн, 26 жовтня")
        XCTAssertEqual(DeveloperPresenter.dayDistance(day(25), today: day(26)), "учора")
        XCTAssertEqual(DeveloperPresenter.dayDistance(day(21), today: day(26)), "5 днів тому")
    }

    func testQuestTemplateShowsParameters() {
        let title = QuestCatalog.definition("daily.halfBy")!.title
        XCTAssertEqual(DeveloperPresenter.questTemplate(title), "Половина до T")
    }
}
