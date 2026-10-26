import XCTest
import Core
import Persistence
import Metrics
@testable import Hydration

/// Режим розробника (WAT-68): норма окремого дня й розкладка об'єму дня на порції.
@MainActor
final class DeveloperHydrationTests: XCTestCase {

    // MARK: - Норма дня

    func testPastDayGoalDoesNotLeakIntoFollowingDays() {
        let env = TestEnv(day: 18, goalMl: 2000)
        let past = DayKey(rawValue: "2026-07-15")
        env.hydration.addIntake(amountMl: 1500, at: env.at(day: 15, hour: 12))

        let snapshot = env.hydration.setGoal(1500, on: past)

        XCTAssertEqual(snapshot.goalMl, 1500)
        XCTAssertEqual(env.profiles.currentGoalMl(on: past), 1500)
        XCTAssertEqual(env.profiles.currentGoalMl(on: DayKey(rawValue: "2026-07-16")), 2000,
                       "наступний день лишається з колишньою нормою")
        XCTAssertEqual(env.hydration.currentGoal(), 2000)
    }

    func testPastDayGoalClosesAndReopensTheDay() {
        let env = TestEnv(day: 18, goalMl: 2000)
        let past = DayKey(rawValue: "2026-07-15")
        env.hydration.addIntake(amountMl: 1500, at: env.at(day: 15, hour: 12))

        XCTAssertTrue(env.hydration.setGoal(1500, on: past).goalMet)
        XCTAssertEqual(env.metrics.sum(.dayGoalMet, periodType: .day, periodKey: past.rawValue), 1)

        XCTAssertFalse(env.hydration.setGoal(2500, on: past).goalMet)
        XCTAssertEqual(env.metrics.sum(.dayGoalMet, periodType: .day, periodKey: past.rawValue), 0,
                       "норму знято — подія відкочена, як після видаленої порції")
    }

    func testTodayGoalIsTheUsualGoalChange() {
        let env = TestEnv(day: 18, goalMl: 2000)
        env.hydration.setGoal(2600, on: DayKey(rawValue: "2026-07-18"))
        XCTAssertEqual(env.hydration.currentGoal(), 2600)
    }

    // MARK: - Заповнення дня

    func testFillSplitsVolumeIntoPortionsAcrossTheDay() {
        let schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        let portions = DayFill.portions(totalMl: 2000, schedule: schedule)

        XCTAssertEqual(portions.map(\.ml).reduce(0, +), 2000)
        XCTAssertTrue(portions.allSatisfy { $0.ml % 50 == 0 && Intake.isValid($0.ml) })
        XCTAssertEqual(portions.first?.minute, 8 * 60)
        XCTAssertLessThanOrEqual(portions.last?.minute ?? .max, 21 * 60 + 30, "не впритул до відбою")
        XCTAssertEqual(portions.map(\.minute), portions.map(\.minute).sorted())
    }

    func testFillTodayStaysInThePast() {
        let schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        let portions = DayFill.portions(totalMl: 1000, schedule: schedule, untilMinute: 9 * 60)

        XCTAssertEqual(portions.map(\.ml).reduce(0, +), 1000)
        XCTAssertTrue(portions.allSatisfy { $0.minute <= 9 * 60 })
        let gaps = zip(portions.dropFirst(), portions).map { $0.minute - $1.minute }
        XCTAssertTrue(gaps.allSatisfy { $0 >= DayFill.minGapMinutes },
                      "порції в одну хвилину відкрили б пасхалки «серією»: \(portions)")
    }

    func testFillOfNothingIsEmpty() {
        XCTAssertTrue(DayFill.portions(totalMl: 0, schedule: .weekdayDefault).isEmpty)
        XCTAssertEqual(DayFill.portions(totalMl: 60, schedule: .weekdayDefault).map(\.ml), [50])
    }
}
