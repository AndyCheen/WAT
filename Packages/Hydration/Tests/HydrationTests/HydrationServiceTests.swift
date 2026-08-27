import XCTest
import Core
import Persistence
import Metrics
@testable import Hydration

@MainActor
final class HydrationServiceTests: XCTestCase {

    func testAddIntakeUpdatesDayAndMetrics() {
        let env = TestEnv()
        let result = env.hydration.addIntake(amountMl: 300)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.day.totalMl, 300)
        XCTAssertEqual(result?.day.completionPct, 15)
        XCTAssertEqual(env.metrics.sumToday(.intakeAdded), 300)
        XCTAssertEqual(env.metrics.sumToday(.intakeCount), 1)
    }

    func testAmountOutsideLimitsIsRejected() {
        let env = TestEnv()
        XCTAssertNil(env.hydration.addIntake(amountMl: 10), "менше 50 мл — відхиляємо")
        XCTAssertNil(env.hydration.addIntake(amountMl: 10_000), "нереалістичний обʼєм — відхиляємо (ТЗ §14)")
        XCTAssertEqual(env.hydration.todaySnapshot().totalMl, 0)
    }

    func testOverflowIsCappedAt120Percent() {
        let env = TestEnv(goalMl: 2000)
        for _ in 0..<3 { env.hydration.addIntake(amountMl: 1000) }

        let day = env.hydration.todaySnapshot()
        XCTAssertEqual(day.totalMl, 3000, "фактично випите зберігається")
        XCTAssertEqual(day.countedMl, 2400, "зараховується не більше 120 % норми")
        XCTAssertTrue(day.isCapped)
        XCTAssertEqual(day.completionPct, 120)
    }

    func testRemoveIntakeRollsBackDayAndMetrics() {
        let env = TestEnv()
        let first = env.hydration.addIntake(amountMl: 500)!
        env.hydration.addIntake(amountMl: 200)

        let after = env.hydration.removeIntake(id: first.intakeId)

        XCTAssertEqual(after?.totalMl, 200)
        XCTAssertEqual(env.metrics.sumToday(.intakeAdded), 200)
        XCTAssertEqual(env.metrics.sumToday(.intakeCount), 1)
        XCTAssertEqual(env.hydration.intakes(for: env.calendar.today).count, 1)
    }

    func testRestoreIntakeReturnsDayToStateBeforeRemoval() {
        let env = TestEnv()
        let first = env.hydration.addIntake(amountMl: 500)!
        env.hydration.addIntake(amountMl: 200)
        let before = env.hydration.todaySnapshot()

        env.hydration.removeIntake(id: first.intakeId)
        let restored = env.hydration.restoreIntake(id: first.intakeId)

        XCTAssertEqual(restored?.totalMl, before.totalMl)
        XCTAssertEqual(restored?.completionPct, before.completionPct)
        XCTAssertEqual(restored?.entriesCount, before.entriesCount)
        XCTAssertEqual(restored?.partTotals, before.partTotals, "порція лишилась у своїй частині доби")
        XCTAssertEqual(env.metrics.sumToday(.intakeAdded), 700, "лічильник відновлено, а не подвоєно")
        XCTAssertEqual(env.metrics.sumToday(.intakeCount), 2)
        XCTAssertEqual(env.hydration.intakes(for: env.calendar.today).count, 2)
    }

    func testRestoreBringsBackGoalMetEvent() {
        let env = TestEnv(goalMl: 1000)
        let closing = env.hydration.addIntake(amountMl: 1000)!
        XCTAssertTrue(closing.goalJustReached)
        XCTAssertEqual(env.metrics.sumToday(.dayGoalMet), 1)

        env.hydration.removeIntake(id: closing.intakeId)
        XCTAssertEqual(env.metrics.sumToday(.dayGoalMet), 0, "норма більше не виконана")

        let restored = env.hydration.restoreIntake(id: closing.intakeId)
        XCTAssertTrue(restored?.goalMet == true)
        XCTAssertEqual(env.metrics.sumToday(.dayGoalMet), 1, "подія «норму виконано» повернулась одна")
    }

    func testRestoreKeepsOriginalTimeEvenAfterMidnight() {
        let env = TestEnv(day: 18, hour: 22)
        let evening = env.hydration.addIntake(amountMl: 400)!
        env.hydration.removeIntake(id: evening.intakeId)

        // Користувач натиснув «Скасувати» вже наступної доби.
        env.clock.set(env.at(day: 19, hour: 1))
        env.hydration.restoreIntake(id: evening.intakeId)

        XCTAssertEqual(env.hydration.snapshot(for: DayKey(rawValue: "2026-07-18")).totalMl, 400,
                       "порція лишилась у своєму дні")
        XCTAssertEqual(env.hydration.todaySnapshot().totalMl, 0, "і не переїхала в новий")
    }

    func testRestoringLiveIntakeIsNoop() {
        let env = TestEnv()
        let result = env.hydration.addIntake(amountMl: 250)!

        XCTAssertNil(env.hydration.restoreIntake(id: result.intakeId), "невидалену порцію відновлювати нема з чого")
        XCTAssertEqual(env.metrics.sumToday(.intakeAdded), 250, "лічильник не подвоївся")
    }

    func testRemovingSameIntakeTwiceIsNoop() {
        let env = TestEnv()
        let result = env.hydration.addIntake(amountMl: 250)!
        env.hydration.removeIntake(id: result.intakeId)

        XCTAssertNil(env.hydration.removeIntake(id: result.intakeId))
        XCTAssertEqual(env.metrics.sumToday(.intakeAdded), 0)
    }

    func testGoalMetEventIsRecordedOnceAndRevertedOnUndo() {
        let env = TestEnv(goalMl: 1000)
        env.hydration.addIntake(amountMl: 500)
        let closing = env.hydration.addIntake(amountMl: 600)!

        XCTAssertTrue(closing.goalJustReached)
        XCTAssertEqual(env.metrics.sumToday(.dayGoalMet), 1)

        env.hydration.addIntake(amountMl: 100)
        XCTAssertEqual(env.metrics.sumToday(.dayGoalMet), 1, "подія «ціль дня» — рівно одна на добу")

        env.hydration.removeIntake(id: closing.intakeId)
        XCTAssertEqual(env.metrics.sumToday(.dayGoalMet), 0, "після відкату ціль дня знову не виконана")
    }

    func testIntakesAreBucketedByDayPart() {
        let env = TestEnv()
        env.hydration.addIntake(amountMl: 200, at: env.at(hour: 7))   // Ранок
        env.hydration.addIntake(amountMl: 300, at: env.at(hour: 10))  // Полудень
        env.hydration.addIntake(amountMl: 500, at: env.at(hour: 14))  // День
        env.hydration.addIntake(amountMl: 250, at: env.at(hour: 19))  // Вечір

        XCTAssertEqual(env.hydration.todaySnapshot().partTotals, [200, 300, 500, 250, 0])
        XCTAssertEqual(env.metrics.sumToday(.partAfternoon), 500)
    }

    func testGoalChangeMidDayAdjustsCurrentDay() {
        let env = TestEnv(goalMl: 2000)
        env.hydration.addIntake(amountMl: 1000)
        XCTAssertEqual(env.hydration.todaySnapshot().completionPct, 50)

        let updated = env.hydration.setGoal(2500)
        XCTAssertEqual(updated.goalMl, 2500)
        XCTAssertEqual(updated.completionPct, 40, "прогрес перераховується під нову норму (ТЗ §14)")
    }

    func testGoalIsClampedToAllowedRange() {
        let env = TestEnv()
        XCTAssertEqual(env.hydration.setGoal(100).goalMl, 500)
        XCTAssertEqual(env.hydration.setGoal(99_000).goalMl, 5000)
    }

    func testPastDayKeepsItsOwnGoalSnapshot() {
        let env = TestEnv(goalMl: 2000)
        env.hydration.addIntake(amountMl: 2000, at: env.at(day: 17, hour: 12))
        env.hydration.setGoal(3000)

        let past = env.hydration.snapshot(for: DayKey(rawValue: "2026-07-17"))
        XCTAssertEqual(past.goalMl, 2000, "минулий день рахується за нормою, що діяла тоді")
        XCTAssertTrue(past.goalMet)
    }

    func testHistoryIsNewestFirstWithTimeLabels() {
        let env = TestEnv()
        env.hydration.addIntake(amountMl: 250, at: env.at(hour: 8, minute: 15))
        env.hydration.addIntake(amountMl: 500, at: env.at(hour: 10, minute: 40))

        let history = env.hydration.intakes(for: env.calendar.today)
        XCTAssertEqual(history.map(\.amountMl), [500, 250])
        XCTAssertEqual(history.map(\.timeLabel), ["10:40", "08:15"])
    }

    func testQuickAddDefaultsMatchMockup() {
        let env = TestEnv()
        XCTAssertEqual(env.hydration.quickAddAmounts(), [200, 500, 1000])
    }
}
