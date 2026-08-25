import XCTest
import Core
@testable import Gamification

@MainActor
final class StreakEngineTests: XCTestCase {

    func testConsecutiveDaysBuildStreak() {
        let env = GameEnv()
        for day in 14...18 { env.completeDay("2026-07-\(day)") }

        XCTAssertEqual(env.game.streakSummary().current, 5)
        XCTAssertEqual(env.game.streakSummary().longest, 5)
    }

    func testGapBreaksStreakButKeepsLongest() {
        let env = GameEnv()
        for day in 10...13 { env.completeDay("2026-07-\(day)") }  // 4 дні
        env.completeDay("2026-07-17")
        env.completeDay("2026-07-18")

        let summary = env.game.streakSummary()
        XCTAssertEqual(summary.current, 2, "після пропуску серія починається спочатку")
        XCTAssertEqual(summary.longest, 4)
    }

    func testYesterdayOnlyKeepsStreakAliveToday() {
        let env = GameEnv()
        env.completeDay("2026-07-16")
        env.completeDay("2026-07-17")

        XCTAssertEqual(env.game.streakSummary().current, 2, "сьогодні ще не закрито — серія не обривається")
    }

    func testFreezeSavesMissedDay() {
        let env = GameEnv()
        env.completeDay("2026-07-15")
        env.completeDay("2026-07-16")
        env.completeDay("2026-07-18")
        XCTAssertEqual(env.game.streakSummary().current, 1, "17-те пропущено")

        env.game.streaks.grantFreezeToken()
        let used = env.game.streaks.useFreeze(on: DayKey(rawValue: "2026-07-17"), at: env.clock.now)

        XCTAssertTrue(used)
        XCTAssertEqual(env.game.streakSummary().current, 4, "заморозка зшиває серію")
        XCTAssertEqual(env.game.streakSummary().freezeTokens, 0)
    }

    func testFreezeWithoutTokenIsRejected() {
        let env = GameEnv()
        XCTAssertFalse(env.game.streaks.useFreeze(on: DayKey(rawValue: "2026-07-17"), at: env.clock.now))
    }
}
