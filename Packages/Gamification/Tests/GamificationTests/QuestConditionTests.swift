import XCTest
import Core
import Persistence
@testable import Gamification

/// Умови дня (SPEC-QUESTS §3, §4.4, §7) — чисті функції на `QuestDay` без бази.
final class QuestConditionTests: XCTestCase {
    private let schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    private func day(_ portions: [(Int, Int, Int)], goalMl: Int = 2000, goalAhead: Bool = false) -> QuestDay {
        QuestDay(day: DayKey(rawValue: "2026-10-21"), goalMl: goalMl, schedule: schedule,
                 portions: portions.map { TimedPortion(minute: $0.0 * 60 + $0.1, ml: $0.2) }, goalAhead: goalAhead)
    }

    /// Д5: порція до підйому теж рахується, дедлайн — W + 60, строго.
    func testWakeGlassCountsPortionBeforeWake() {
        let condition = DayCondition.wakeGlass(withinMinutes: 60)
        XCTAssertTrue(condition.evaluate(on: day([(7, 30, 250)]), params: QuestParams()).met)
        XCTAssertFalse(condition.evaluate(on: day([(9, 0, 250)]), params: QuestParams()).met, "о 09:00 — уже після T")
        XCTAssertEqual(condition.deadline(on: day([]), params: QuestParams()), 9 * 60)
        XCTAssertTrue(condition.evaluate(on: day([(8, 59, 250)]), params: QuestParams()).met)
        // P менша за 250 — ціль P; більша — 250.
        XCTAssertTrue(condition.evaluate(on: day([(8, 30, 200)]), params: QuestParams(glassMl: 200)).met)
        XCTAssertFalse(condition.evaluate(on: day([(8, 30, 200)]), params: QuestParams(glassMl: 400)).met)
    }

    /// «До T» — строго раніше, T із інстансу.
    func testShareByIsStrictlyBeforeDeadline() {
        let condition = DayCondition.shareBy(0.5, .curveShare(0.5))
        let params = QuestParams(deadlineMinute: 14 * 60)
        XCTAssertTrue(condition.evaluate(on: day([(13, 59, 1000)]), params: params).met)
        XCTAssertFalse(condition.evaluate(on: day([(14, 0, 1000)]), params: params).met)
        XCTAssertEqual(condition.evaluate(on: day([(10, 0, 400)]), params: params).target, 1000)
    }

    /// T½ і W + 3 год — униз до 30 хв (§4.4).
    func testDeadlinesRoundDownToHalfHour() {
        let late = QuestDay(day: DayKey(rawValue: "2026-10-21"), goalMl: 2000,
                            schedule: DaySchedule(wakeMinutes: 7 * 60 + 15, sleepMinutes: 22 * 60), portions: [])
        XCTAssertEqual(DayCondition.shareBy(0.25, .wakePlus(minutes: 180)).deadline(on: late, params: QuestParams()), 10 * 60)
        let half = DayCondition.shareBy(0.5, .curveShare(0.5)).deadline(on: day([]), params: QuestParams())!
        XCTAssertEqual(half % 30, 0)
        XCTAssertLessThanOrEqual(Double(half), day([]).curve.minute(reaching: 1000)!)
    }

    /// Особистий дедлайн: медіана − 30, у межах [Z − 4 год, Z − 2 год], униз до 30; без медіани — Z − 3 год.
    func testPersonalGoalDeadline() {
        XCTAssertEqual(QuestRules.personalGoalMinute(median: nil, sleepMinutes: 22 * 60), 19 * 60)
        XCTAssertEqual(QuestRules.personalGoalMinute(median: 19 * 60 + 10, sleepMinutes: 22 * 60), 18 * 60 + 30)
        XCTAssertEqual(QuestRules.personalGoalMinute(median: 15 * 60, sleepMinutes: 22 * 60), 18 * 60, "не раніше Z − 4 год")
        XCTAssertEqual(QuestRules.personalGoalMinute(median: 21 * 60 + 50, sleepMinutes: 22 * 60), 20 * 60, "не пізніше Z − 2 год")
    }

    /// Д8: порція до підйому — першому блоку, дрібна — не рахується.
    func testPortionInEachBlock() {
        let condition = DayCondition.portionInEachBlock(minMl: 150)
        let blocks = day([]).blocks.count
        XCTAssertEqual(blocks, 3)
        XCTAssertTrue(condition.evaluate(on: day([(6, 30, 200), (13, 0, 200), (19, 0, 200)]), params: QuestParams()).met)
        let small = condition.evaluate(on: day([(9, 0, 200), (13, 0, 100), (19, 0, 200)]), params: QuestParams())
        XCTAssertFalse(small.met)
        XCTAssertEqual(small.progress, 2)
    }

    /// Д6: N порцій від 150 мл; 100 мл не рахується.
    func testGlassesNeedRealGlasses() {
        let condition = DayCondition.glasses(minMl: 150, deadline: nil)
        let result = condition.evaluate(on: day([(9, 0, 250), (10, 0, 100), (11, 0, 150)]), params: QuestParams(count: 3))
        XCTAssertEqual(result.progress, 2)
        XCTAssertFalse(result.met)
    }

    /// Унції: ціль 250 мл показується як 8 унц. і порівнюється з 237 мл — 8 унц. зараховано (WAT-59).
    func testOuncesCompareWithShownNumber() {
        let ounces = QuestParams(glassMl: 250, unit: .usFluidOunces)
        let eight = VolumeUnit.usFluidOunces.milliliters(units: 8)
        XCTAssertTrue(DayCondition.wakeGlass(withinMinutes: 60).evaluate(on: day([(8, 30, eight)]), params: ounces).met)
        XCTAssertFalse(DayCondition.wakeGlass(withinMinutes: 60).evaluate(on: day([(8, 30, eight)]), params: QuestParams()).met)
        // «Від 150 мл» в унціях — «від 5 унц.».
        let five = VolumeUnit.usFluidOunces.milliliters(units: 5)
        XCTAssertEqual(DayCondition.glasses(minMl: 150, deadline: nil)
            .evaluate(on: day([(9, 0, five)]), params: QuestParams(count: 1, unit: .usFluidOunces)).progress, 1)
        XCTAssertEqual(QuestRules.shownMl(510, unit: .milliliters), 500)
    }

    /// Д4: норма й жодного нагадування до неї (`day.goalAhead`).
    func testGoalAhead() {
        XCTAssertFalse(DayCondition.goalAhead.evaluate(on: day([(12, 0, 2000)]), params: QuestParams()).met)
        XCTAssertTrue(DayCondition.goalAhead.evaluate(on: day([(12, 0, 2000)], goalAhead: true), params: QuestParams()).met)
        XCTAssertFalse(DayCondition.goalAhead.evaluate(on: day([(12, 0, 1000)], goalAhead: true), params: QuestParams()).met)
    }

    func testBlockReachedAndAllBlocks() {
        let targets = day([]).blocks.map(\.targetMl)
        let full = day([(9, 0, targets[0]), (14, 0, targets[1]), (19, 0, targets[2])])
        XCTAssertTrue(DayCondition.allBlocks.evaluate(on: full, params: QuestParams()).met)
        XCTAssertTrue(DayCondition.blockReached.evaluate(on: full, params: QuestParams(blockIndex: 2)).met)
        let morningOnly = day([(9, 0, targets[0])])
        XCTAssertTrue(DayCondition.blockReached.evaluate(on: morningOnly, params: QuestParams(blockIndex: 0)).met)
        XCTAssertFalse(DayCondition.blockReached.evaluate(on: morningOnly, params: QuestParams(blockIndex: 1)).met)
        XCTAssertEqual(DayCondition.allBlocks.evaluate(on: morningOnly, params: QuestParams()).progress, 1)
    }

    /// Тижневі: лік днів, найдовший ланцюжок і вихідні.
    func testWeeklyConditions() {
        let days = (19...25).map { index in
            QuestDay(day: DayKey(rawValue: "2026-10-\(index)"), goalMl: 2000, schedule: schedule,
                     portions: [19, 20, 22, 23, 24].contains(index) ? [TimedPortion(minute: 600, ml: 2000)] : [])
        }
        let params = QuestParams(count: 3)
        XCTAssertEqual(QuestCondition.daysCount(.goal).evaluate(days: days, params: params).progress, 5)
        XCTAssertEqual(QuestCondition.daysRun(.goal).evaluate(days: days, params: params).progress, 3, "Чт–Сб")
        let weekend = QuestCondition.weekend(.goal).evaluate(days: days, params: params)
        XCTAssertEqual(weekend.progress, 1, "субота так, неділя — ні")
        XCTAssertFalse(weekend.met)
    }
}
