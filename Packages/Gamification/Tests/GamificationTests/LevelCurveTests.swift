import XCTest
@testable import Gamification

final class LevelCurveTests: XCTestCase {
    private let curve = LinearLevelCurve()

    func testFirstLevelsRequireGrowingXP() {
        XCTAssertEqual(curve.xpToNext(after: 1), 100)
        XCTAssertEqual(curve.xpToNext(after: 2), 150)
        XCTAssertEqual(curve.xpToNext(after: 7), 400)
    }

    func testProgressAtZeroXP() {
        let p = LevelCalculator.progress(totalXp: 0, curve: curve)
        XCTAssertEqual(p.level, 1)
        XCTAssertEqual(p.xpIntoLevel, 0)
        XCTAssertEqual(p.xpForNextLevel, 100)
        XCTAssertEqual(p.fraction, 0)
    }

    func testProgressCrossesLevels() {
        // 100 + 150 = 250 XP → рівно 3-й рівень
        let p = LevelCalculator.progress(totalXp: 250, curve: curve)
        XCTAssertEqual(p.level, 3)
        XCTAssertEqual(p.xpIntoLevel, 0)
        XCTAssertEqual(p.xpForNextLevel, 200)
    }

    func testProgressInsideLevel() {
        let p = LevelCalculator.progress(totalXp: 300, curve: curve)
        XCTAssertEqual(p.level, 3)
        XCTAssertEqual(p.xpIntoLevel, 50)
        XCTAssertEqual(p.xpLeft, 150)
        XCTAssertEqual(p.nextLevel, 4)
    }

    func testTotalXpRequiredMatchesProgress() {
        for level in 1...30 {
            let total = LevelCalculator.totalXpRequired(forLevel: level, curve: curve)
            XCTAssertEqual(LevelCalculator.progress(totalXp: total, curve: curve).level, level)
        }
    }

    func testStreakMultiplierIsCapped() {
        let rules = XPRules.default
        XCTAssertEqual(rules.multiplier(streak: 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(rules.multiplier(streak: 4), 1.2, accuracy: 0.001)
        XCTAssertEqual(rules.multiplier(streak: 100), 1.5, accuracy: 0.001, "множник обмежений стелею")
    }
}
