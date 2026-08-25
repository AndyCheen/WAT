import XCTest
import SwiftData
import Core
@testable import Persistence

@MainActor
final class RepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var profiles: ProfileRepository!
    private var dayLogs: DayLogRepository!
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = Database.makeInMemoryContainer()
        profiles = ProfileRepository(context: container.mainContext)
        dayLogs = DayLogRepository(context: container.mainContext)
    }

    // MARK: - Профіль і норма

    func testProfileIsCreatedOnceAndReused() {
        let first = profiles.profile()
        first.weightKg = 72
        let second = profiles.profile()
        XCTAssertEqual(second.weightKg, 72, "профіль — єдиний рядок")
    }

    func testGoalRevisionsAreLookedUpByDate() {
        profiles.setGoal(2000, source: .onboarding, effectiveFrom: DayKey(rawValue: "2026-07-01"), at: now)
        profiles.setGoal(2500, source: .manual, effectiveFrom: DayKey(rawValue: "2026-07-15"), at: now)

        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-07-10")), 2000)
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-07-15")), 2500)
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-08-01")), 2500)
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-06-01")), 2000, "до першої ревізії — стандартна норма")
    }

    func testSecondGoalOnSameDayUpdatesRevision() {
        profiles.setGoal(2000, source: .manual, effectiveFrom: DayKey(rawValue: "2026-07-18"), at: now)
        profiles.setGoal(2400, source: .manual, effectiveFrom: DayKey(rawValue: "2026-07-18"), at: now)

        XCTAssertEqual(profiles.goalRevisions().count, 1, "одна доба — одна ревізія")
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-07-18")), 2400)
    }

    func testGoalIsClamped() {
        profiles.setGoal(50, source: .manual, effectiveFrom: DayKey(rawValue: "2026-07-18"), at: now)
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-07-18")), GoalRevision.minGoalMl)

        profiles.setGoal(50_000, source: .manual, effectiveFrom: DayKey(rawValue: "2026-07-19"), at: now)
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-07-19")), GoalRevision.maxGoalMl)
    }

    func testQuickAddPresetsSeedOnceWithMockupValues() {
        let first = profiles.quickAddPresets()
        XCTAssertEqual(first.map(\.amountMl), [200, 500, 1000])
        XCTAssertEqual(profiles.quickAddPresets().count, 3, "повторний виклик не дублює пресети")
    }

    // MARK: - Денні логи

    func testDayLogIsUniquePerDay() {
        let first = dayLogs.dayLog(for: DayKey(rawValue: "2026-07-18"), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        let second = dayLogs.dayLog(for: DayKey(rawValue: "2026-07-18"), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        XCTAssertTrue(first === second)
        XCTAssertEqual(dayLogs.allDayLogs().count, 1)
    }

    func testRangeAndMonthQueries() {
        for day in ["2026-06-30", "2026-07-01", "2026-07-15", "2026-07-31", "2026-08-01"] {
            _ = dayLogs.dayLog(for: DayKey(rawValue: day), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        }

        let july = dayLogs.dayLogs(in: MonthKey(year: 2026, month: 7))
        XCTAssertEqual(july.map(\.dayKey), ["2026-07-01", "2026-07-15", "2026-07-31"])

        let range = dayLogs.dayLogs(from: DayKey(rawValue: "2026-07-01"), to: DayKey(rawValue: "2026-07-15"))
        XCTAssertEqual(range.count, 2)
    }

    func testEarliestDayKey() {
        XCTAssertNil(dayLogs.earliestDayKey())
        for day in ["2026-07-18", "2026-05-02", "2026-06-11"] {
            _ = dayLogs.dayLog(for: DayKey(rawValue: day), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        }
        XCTAssertEqual(dayLogs.earliestDayKey()?.rawValue, "2026-05-02")
    }

    func testSoftDeletedIntakesAreExcluded() {
        let key = DayKey(rawValue: "2026-07-18")
        let log = dayLogs.dayLog(for: key, goalMl: 2000, timeZoneId: "Europe/Kyiv")
        let kept = Intake(amountMl: 300, createdAt: now)
        let removed = Intake(amountMl: 200, createdAt: now)
        dayLogs.insert(kept, into: log)
        dayLogs.insert(removed, into: log)
        removed.deletedAt = now
        dayLogs.save()

        XCTAssertEqual(dayLogs.activeIntakes(for: key).map(\.amountMl), [300])
        XCTAssertNotNil(dayLogs.intake(id: removed.id), "запис лишається в базі для аудиту")
    }

    func testIntakeLimits() {
        XCTAssertTrue(Intake.isValid(50))
        XCTAssertTrue(Intake.isValid(2000))
        XCTAssertFalse(Intake.isValid(49))
        XCTAssertFalse(Intake.isValid(2001))
        XCTAssertEqual(Intake.clamp(10_000), 2000)
    }

    func testDayLogCapAndCompletion() {
        let log = dayLogs.dayLog(for: DayKey(rawValue: "2026-07-18"), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        log.totalMl = 3000
        log.countedMl = min(log.totalMl, log.capMl)

        XCTAssertEqual(log.capMl, 2400, "стеля — 120 % норми")
        XCTAssertEqual(log.countedMl, 2400)
        XCTAssertEqual(log.completionPct, 120)
        XCTAssertTrue(log.isCapped)
        XCTAssertTrue(log.goalMet)
    }

    func testSchemaCoversEveryModel() {
        XCTAssertEqual(Database.schema.entities.count, 14, "усі 14 таблиць у схемі (PLAN.md §3.2)")
    }
}
