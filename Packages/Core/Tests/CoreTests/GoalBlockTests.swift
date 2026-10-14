import XCTest
@testable import Core

/// Цілі частин доби — SPEC-NOTIFICATIONS §9, §32: завжди ранок, день і вечір; при 08:00–22:00 чекпоінти «до 12:00» і «до 17:00»,
/// цілі 689 і 826 мл (різниці округлених E: 1515 − 689), разом із вечором — рівно норма.
final class GoalBlockTests: XCTestCase {
    private func blocks(_ wake: Int, _ sleep: Int, goal: Int = 2000) -> [GoalBlock] {
        PaceCurve(goalMl: goal, wakeMinutes: wake, sleepMinutes: sleep).goalBlocks()
    }

    func testDefaultHoursMergeMorningIntoNoon() {
        let result = blocks(8 * 60, 22 * 60)
        XCTAssertEqual(result.map(\.parts), [[.morning, .noon], [.afternoon], [.evening]])
        XCTAssertEqual(result.map(\.fromMinute), [8 * 60, 12 * 60, 17 * 60])
        XCTAssertEqual(result.map(\.toMinute), [12 * 60, 17 * 60, 22 * 60])
        XCTAssertEqual(result.map(\.targetMl), [689, 826, 485])
        XCTAssertEqual(result.map(\.targetMl).reduce(0, +), 2000)
        XCTAssertEqual(result.map(\.kind), [.morning, .day, .evening])
        XCTAssertEqual(result.map(\.title), ["ранок", "день", "вечір"])
    }

    // MARK: - Завжди ранок, день і вечір (WAT-48, §32)

    /// Ранній підйом подовжує ранок, а не додає блок: раніше 06:00–22:00 давало окремий «ранок 06–09».
    func testEarlyWakeExtendsMorning() {
        let result = blocks(6 * 60, 22 * 60)
        XCTAssertEqual(result.map(\.kind), [.morning, .day, .evening])
        XCTAssertEqual(result.map(\.parts), [[.morning, .noon], [.afternoon], [.evening]])
        XCTAssertEqual(result.map(\.fromMinute), [6 * 60, 12 * 60, 17 * 60])
    }

    /// Пізній відбій подовжує вечір: «ніч 22–24» з ціллю 29 мл закривалась одним ковтком.
    func testLateSleepExtendsEvening() {
        let result = blocks(8 * 60, 24 * 60)
        XCTAssertEqual(result.map(\.kind), [.morning, .day, .evening])
        XCTAssertEqual(result.last?.parts, [.evening, .night])
        XCTAssertEqual(result.last?.toMinute, 24 * 60)
        XCTAssertEqual(result.last?.key, "evening", "ключ вечора не залежить від відбою")
    }

    /// Будь-який звичайний розклад — рівно три блоки.
    func testUsualSchedulesAlwaysGiveThreeBlocks() {
        for (wake, sleep) in [(4 * 60, 22 * 60), (6 * 60, 24 * 60), (7 * 60, 22 * 60), (7 * 60 + 15, 22 * 60),
                              (8 * 60, 23 * 60), (9 * 60, 23 * 60), (10 * 60, 24 * 60)] {
            XCTAssertEqual(blocks(wake, sleep).map(\.kind), [.morning, .day, .evening], "\(wake)–\(sleep)")
        }
    }

    /// Ключі — ті, якими блоки закінчувались при 08:00–22:00 до WAT-48: XP за сьогодні не дублюється.
    func testKeysKeepPreviousDefaultValues() {
        XCTAssertEqual(blocks(8 * 60, 22 * 60).map(\.key), ["noon", "afternoon", "evening"])
    }

    /// Підйом після 10:00 — ранок коротший за 2 год зливається з днем і бере його назву.
    func testLateWakeMergesMorningIntoDay() {
        let result = blocks(10 * 60 + 30, 21 * 60)
        XCTAssertEqual(result.map(\.kind), [.day, .evening])
        XCTAssertEqual(result.map(\.parts), [[.noon, .afternoon], [.evening]])
        XCTAssertEqual(result.map(\.targetMl).reduce(0, +), 2000)
    }

    /// Відбій до 19:00 — вечір коротший за 2 год зливається з днем.
    func testEarlySleepMergesEveningIntoDay() {
        let result = blocks(6 * 60, 18 * 60)
        XCTAssertEqual(result.map(\.kind), [.morning, .day])
        XCTAssertEqual(result.last?.toMinute, 18 * 60)
    }

    /// Підйом о 04:00 і відбій о 24:00: ніч на початку доби — ранок, наприкінці — вечір.
    func testNightOnBothEndsGoesToEdgeBlocks() {
        let result = blocks(4 * 60, 24 * 60)
        XCTAssertEqual(result.map(\.parts), [[.night, .morning, .noon], [.afternoon], [.evening, .night]])
        // Порція о 23:00 належить вечору, а не ранку.
        let late = [TimedPortion(minute: 23 * 60, ml: 300)]
        XCTAssertEqual(result[0].drunkMl(of: late), 0)
        XCTAssertEqual(result[2].drunkMl(of: late), 300)
    }

    func testDrunkCountsOnlyPortionsInsideBlock() {
        let block = blocks(8 * 60, 22 * 60)[1]
        let portions = [
            TimedPortion(minute: 11 * 60 + 59, ml: 400),  // попередній блок
            TimedPortion(minute: 12 * 60, ml: 300),       // межа належить цьому блоку
            TimedPortion(minute: 16 * 60 + 59, ml: 250),
            TimedPortion(minute: 17 * 60, ml: 200)        // уже наступний
        ]
        XCTAssertEqual(block.drunkMl(of: portions), 550)
        XCTAssertFalse(block.isReached(by: portions))
    }

    // MARK: - Краї дня (WAT-39)

    /// Склянка о 06:30 при підйомі о 08:00 — це ранок: зараховується першому блоку.
    func testPortionBeforeWakeCountsToFirstBlock() {
        let result = blocks(8 * 60, 22 * 60)
        let portions = [
            TimedPortion(minute: 6 * 60 + 30, ml: 250),
            TimedPortion(minute: 9 * 60, ml: 200),
            TimedPortion(minute: 11 * 60, ml: 250)
        ]
        XCTAssertEqual(result[0].drunkMl(of: portions), 700)
        XCTAssertTrue(result[0].isReached(by: portions))
        XCTAssertEqual(result[1].drunkMl(of: portions), 0)
    }

    /// Склянка о 22:30 при відбої о 22:00 — останньому блоку; межі цілі від цього не змінюються.
    func testPortionAfterSleepCountsToLastBlock() {
        let result = blocks(8 * 60, 22 * 60)
        let late = [TimedPortion(minute: 22 * 60 + 30, ml: 300), TimedPortion(minute: 23 * 60 + 59, ml: 100)]
        XCTAssertEqual(result[2].drunkMl(of: late), 400)
        XCTAssertEqual(result[0].drunkMl(of: late) + result[1].drunkMl(of: late), 0)
        XCTAssertEqual(result[2].toMinute, 22 * 60)
        XCTAssertEqual(result[0].fromMinute, 8 * 60)
    }

    /// Один блок на весь день забирає і ранні, і пізні порції.
    func testSingleBlockTakesBothEdges() {
        let result = blocks(12 * 60, 15 * 60)
        XCTAssertEqual(result.count, 1)
        let portions = [TimedPortion(minute: 60, ml: 100), TimedPortion(minute: 23 * 60, ml: 100)]
        XCTAssertEqual(result[0].drunkMl(of: portions), 200)
    }

    func testBlockContainingMinute() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        XCTAssertEqual(curve.goalBlock(containing: 13 * 60)?.kind, .day)
        XCTAssertEqual(curve.goalBlock(containing: 23 * 60)?.kind, .evening, "після відбою — останній блок")
        XCTAssertEqual(curve.goalBlock(containing: 7 * 60)?.kind, .morning, "до підйому — перший блок")
        XCTAssertEqual(curve.goalBlock(containing: 0)?.kind, .morning)
    }

    func testNoBlocksWithoutActiveHours() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 10 * 60, sleepMinutes: 10 * 60)
        XCTAssertTrue(curve.goalBlocks().isEmpty)
        XCTAssertNil(curve.goalBlock(containing: 10 * 60))
    }

    // MARK: - Цілі частин доби для графіків 4a

    /// Ті самі мілілітри, що в блоках: ранок 138 + полудень 551 = 689 до 12:00; ніч поза
    /// активними годинами — 0; сума — рівно норма.
    func testPartTargetsMatchBlocks() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        let targets = curve.partTargetsMl()
        XCTAssertEqual(targets, [138, 551, 826, 485, 0])
        XCTAssertEqual(targets.reduce(0, +), 2000)
        let blocks = curve.goalBlocks()
        XCTAssertEqual(targets[DayPart.morning.rawValue] + targets[DayPart.noon.rawValue], blocks[0].targetMl)
        XCTAssertEqual(targets[DayPart.afternoon.rawValue], blocks[1].targetMl)
        XCTAssertEqual(curve.partShares().reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(curve.partShares()[DayPart.night.rawValue], 0)
    }

    /// Ніч на обох кінцях доби — два відрізки однієї частини, на графіку одне число.
    func testPartTargetsSumNightPieces() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 4 * 60, sleepMinutes: 24 * 60)
        let targets = curve.partTargetsMl()
        XCTAssertGreaterThan(targets[DayPart.night.rawValue], 0)
        XCTAssertEqual(targets.reduce(0, +), 2000)
    }

    /// Порізні округлення не дають «губити» мілілітр на будь-якій нормі й розкладі.
    func testRoundedTargetsAlwaysSumToGoal() {
        for goal in [1500, 1999, 2000, 2350, 3333] {
            for (wake, sleep) in [(6 * 60, 23 * 60), (7 * 60 + 15, 21 * 60 + 45), (10 * 60 + 30, 24 * 60)] {
                let curve = PaceCurve(goalMl: goal, wakeMinutes: wake, sleepMinutes: sleep)
                XCTAssertEqual(curve.partTargetsMl().reduce(0, +), goal, "\(goal) \(wake)–\(sleep)")
                XCTAssertEqual(curve.goalBlocks().map(\.targetMl).reduce(0, +), goal, "\(goal) \(wake)–\(sleep)")
            }
        }
    }

    // MARK: - Поточна частина доби на головному (WAT-40)

    private let day = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    /// Критерій приймання WAT-40: 300 + 250 мл до 11:25 — до 12:00 бракує 139 мл, лишається 35 хв.
    func testProgressBeforeNoonCheckpoint() throws {
        let portions = [TimedPortion(minute: 9 * 60 + 10, ml: 300), TimedPortion(minute: 10 * 60 + 40, ml: 250)]
        let progress = try XCTUnwrap(day.dayPartProgress(atMinute: 11 * 60 + 25, portions: portions))
        XCTAssertEqual(progress.block.toMinute, 12 * 60)
        XCTAssertEqual(progress.drunkMl, 550)
        XCTAssertEqual(progress.leftMl, 139)
        XCTAssertEqual(progress.minutesLeft, 35)
        XCTAssertFalse(progress.isReached)
    }

    func testProgressReachedOnceTargetIsDrunk() throws {
        let portions = [TimedPortion(minute: 9 * 60, ml: 450), TimedPortion(minute: 11 * 60 + 40, ml: 250)]
        let progress = try XCTUnwrap(day.dayPartProgress(atMinute: 11 * 60 + 40, portions: portions))
        XCTAssertTrue(progress.isReached)
        XCTAssertEqual(progress.leftMl, 0)
        XCTAssertEqual(progress.fraction, 1)
    }

    /// Межа належить наступній частині: о 12:00 ранкові порції вже не рахуються.
    func testProgressSwitchesBlockAtBoundary() throws {
        let portions = [TimedPortion(minute: 9 * 60, ml: 700)]
        let progress = try XCTUnwrap(day.dayPartProgress(atMinute: 12 * 60, portions: portions))
        XCTAssertEqual(progress.block.parts, [.afternoon])
        XCTAssertEqual(progress.drunkMl, 0)
        XCTAssertEqual(progress.minutesLeft, 5 * 60)
    }

    func testNoProgressOutsideActiveHours() {
        XCTAssertNil(day.dayPartProgress(atMinute: 7 * 60 + 59, portions: []))
        XCTAssertNil(day.dayPartProgress(atMinute: 22 * 60, portions: []))
        XCTAssertNotNil(day.dayPartProgress(atMinute: 21 * 60 + 59, portions: []))
    }

    /// Склянка до підйому вже в ранковому блоці — о 08:00 рядок її бачить, як і XP.
    func testProgressCountsPortionBeforeWake() throws {
        let progress = try XCTUnwrap(day.dayPartProgress(atMinute: 8 * 60, portions: [TimedPortion(minute: 6 * 60 + 30, ml: 250)]))
        XCTAssertEqual(progress.drunkMl, 250)
    }
}
