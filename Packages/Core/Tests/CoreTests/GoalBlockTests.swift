import XCTest
@testable import Core

/// Цілі частин доби — SPEC-NOTIFICATIONS §9: при 08:00–22:00 чекпоінти «до 12:00» і «до 17:00»,
/// цілі 649 і 780 мл (різниці округлених E: 1429 − 649), разом із вечором — рівно норма.
final class GoalBlockTests: XCTestCase {
    private func blocks(_ wake: Int, _ sleep: Int, goal: Int = 2000) -> [GoalBlock] {
        PaceCurve(goalMl: goal, wakeMinutes: wake, sleepMinutes: sleep).goalBlocks()
    }

    func testDefaultHoursMergeMorningIntoNoon() {
        let result = blocks(8 * 60, 22 * 60)
        XCTAssertEqual(result.map(\.parts), [[.morning, .noon], [.afternoon], [.evening]])
        XCTAssertEqual(result.map(\.fromMinute), [8 * 60, 12 * 60, 17 * 60])
        XCTAssertEqual(result.map(\.toMinute), [12 * 60, 17 * 60, 22 * 60])
        XCTAssertEqual(result.map(\.targetMl), [649, 780, 571])
        XCTAssertEqual(result.map(\.targetMl).reduce(0, +), 2000)
        XCTAssertEqual(result[0].deadlinePart, .noon)
        XCTAssertEqual(result[0].title, "ранок і полудень")
    }

    /// Короткий хвіст ночі (22–23) зливається з попередньою частиною — останньою немає з ким іще.
    func testShortLastPartMergesBackwards() {
        let result = blocks(6 * 60, 23 * 60)
        XCTAssertEqual(result.map(\.parts), [[.morning], [.noon], [.afternoon], [.evening, .night]])
        XCTAssertEqual(result.last?.toMinute, 23 * 60)
    }

    func testLateWakeMergesNoonIntoAfternoon() {
        let result = blocks(10 * 60 + 30, 21 * 60)
        XCTAssertEqual(result.map(\.parts), [[.noon, .afternoon], [.evening]])
        XCTAssertEqual(result.map(\.targetMl).reduce(0, +), 2000)
    }

    /// Підйом о 04:00 і відбій о 24:00: ніч дає два відрізки — на початку й наприкінці доби.
    func testNightOnBothEndsStaysSeparate() {
        let result = blocks(4 * 60, 24 * 60)
        XCTAssertEqual(result.map(\.parts), [[.night, .morning], [.noon], [.afternoon], [.evening], [.night]])
        // Порція о 23:00 належить останньому блоку, а не ранковому.
        let late = [TimedPortion(minute: 23 * 60, ml: 300)]
        XCTAssertEqual(result[0].drunkMl(of: late), 0)
        XCTAssertEqual(result[4].drunkMl(of: late), 300)
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
            TimedPortion(minute: 11 * 60, ml: 200)
        ]
        XCTAssertEqual(result[0].drunkMl(of: portions), 650)
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
        XCTAssertEqual(curve.goalBlock(containing: 13 * 60)?.deadlinePart, .afternoon)
        XCTAssertEqual(curve.goalBlock(containing: 23 * 60)?.deadlinePart, .evening, "після відбою — останній блок")
        XCTAssertEqual(curve.goalBlock(containing: 7 * 60)?.deadlinePart, .noon, "до підйому — перший блок")
        XCTAssertEqual(curve.goalBlock(containing: 0)?.deadlinePart, .noon)
    }

    func testNoBlocksWithoutActiveHours() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 10 * 60, sleepMinutes: 10 * 60)
        XCTAssertTrue(curve.goalBlocks().isEmpty)
        XCTAssertNil(curve.goalBlock(containing: 10 * 60))
    }

    // MARK: - Цілі частин доби для графіків 4a

    /// Ті самі мілілітри, що в блоках: ранок 130 + полудень 519 = 649 до 12:00; ніч поза
    /// активними годинами — 0; сума — рівно норма.
    func testPartTargetsMatchBlocks() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        let targets = curve.partTargetsMl()
        XCTAssertEqual(targets, [130, 519, 780, 571, 0])
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
}
