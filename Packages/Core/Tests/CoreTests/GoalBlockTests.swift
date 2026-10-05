import XCTest
@testable import Core

/// Цілі частин доби — SPEC-NOTIFICATIONS §9: при 08:00–22:00 чекпоінти «до 12:00» і «до 17:00»,
/// цілі 649 і 779 мл.
final class GoalBlockTests: XCTestCase {
    private func blocks(_ wake: Int, _ sleep: Int, goal: Int = 2000) -> [GoalBlock] {
        PaceCurve(goalMl: goal, wakeMinutes: wake, sleepMinutes: sleep).goalBlocks()
    }

    func testDefaultHoursMergeMorningIntoNoon() {
        let result = blocks(8 * 60, 22 * 60)
        XCTAssertEqual(result.map(\.parts), [[.morning, .noon], [.afternoon], [.evening]])
        XCTAssertEqual(result.map(\.fromMinute), [8 * 60, 12 * 60, 17 * 60])
        XCTAssertEqual(result.map(\.toMinute), [12 * 60, 17 * 60, 22 * 60])
        XCTAssertEqual(result.map(\.targetMl), [649, 779, 571])
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
        XCTAssertEqual(result.map(\.targetMl).reduce(0, +), 2000, accuracy: 1)
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
        let block = blocks(8 * 60, 22 * 60)[0]
        let portions = [
            TimedPortion(minute: 7 * 60, ml: 200),       // до підйому — не рахується
            TimedPortion(minute: 8 * 60 + 30, ml: 250),
            TimedPortion(minute: 11 * 60 + 59, ml: 400),
            TimedPortion(minute: 12 * 60, ml: 300)       // межа належить наступному блоку
        ]
        XCTAssertEqual(block.drunkMl(of: portions), 650)
        XCTAssertTrue(block.isReached(by: portions))
    }

    func testBlockContainingMinute() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        XCTAssertEqual(curve.goalBlock(containing: 13 * 60)?.deadlinePart, .afternoon)
        XCTAssertNil(curve.goalBlock(containing: 23 * 60))
        XCTAssertNil(curve.goalBlock(containing: 7 * 60))
    }
}
