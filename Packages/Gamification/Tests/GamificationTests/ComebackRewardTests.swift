import XCTest
import Core
import Persistence
import Metrics
@testable import Gamification

/// Нагороди за повернення — SPEC-NOTIFICATIONS §12.5. Годинник — 18.07.2026, 14:00.
extension GameEnv {
    /// Порція з денним логом: подарунок дивиться на `entriesCount`, а не лише на метрику.
    @discardableResult
    func addIntake(_ ml: Int = 250, on key: String, hour: Int = 10) -> UUID {
        let day = DayKey(rawValue: key)
        let log = dayLogs.dayLog(for: day, goalMl: 2000, timeZoneId: "Europe/Kyiv")
        log.entriesCount += 1
        log.totalMl += ml
        log.countedMl += ml
        dayLogs.save()

        let ref = UUID()
        let date = Self.date(day: day.day, hour: hour, month: day.month, year: day.year)
        metrics.record(MetricEvent(name: .intakeAdded, value: Double(ml), occurredAt: date, sourceRef: ref))
        metrics.record(MetricEvent(name: .intakeCount, value: 1, occurredAt: date, sourceRef: ref))
        return ref
    }

    var comebackGifts: [RewardItem] { store.rewardItems().filter { $0.source == .comeback } }
}

/// А. ⚡ «Подвійний XP» за першу порцію після перерви ≥ 3 днів (§12.5 А, критерій §19.16).
@MainActor
final class ComebackRewardTests: XCTestCase {

    func testFirstIntakeAfterThreeDayGapGivesBoost() {
        let env = GameEnv()
        env.addIntake(on: "2026-07-15")
        _ = env.game.takeRecentUnlocks()

        env.addIntake(on: "2026-07-18")

        XCTAssertEqual(env.comebackGifts.count, 1)
        XCTAssertEqual(env.comebackGifts.first?.defKey, RewardCatalog.boostKey)
        XCTAssertEqual(env.comebackGifts.first?.state, .ready, "звичайний приз, діє лише після активації")
        XCTAssertEqual(env.game.takeRecentUnlocks().comebackGift?.key, RewardCatalog.boostKey, "тост «З поверненням»")
    }

    /// `daysBetween = 2` — лише один порожній день між порціями, це ще не перерва.
    func testShortGapGivesNothing() {
        let env = GameEnv()
        env.addIntake(on: "2026-07-16")
        env.addIntake(on: "2026-07-18")
        XCTAssertTrue(env.comebackGifts.isEmpty)
    }

    func testOnlyFirstIntakeOfTheDayCounts() {
        let env = GameEnv()
        env.addIntake(on: "2026-07-14")
        env.addIntake(on: "2026-07-18", hour: 9)
        env.addIntake(on: "2026-07-18", hour: 11)
        XCTAssertEqual(env.comebackGifts.count, 1)
    }

    func testNewUserWithoutHistoryGetsNothing() {
        let env = GameEnv()
        env.addIntake(on: "2026-07-18")
        XCTAssertTrue(env.comebackGifts.isEmpty, "перша порція в житті — не повернення")
    }

    /// Виданий приз не відкликається (SPEC-PRIZES §3.4) — зловживання обмежує частота.
    func testUndoKeepsTheGift() {
        let env = GameEnv()
        env.addIntake(on: "2026-07-14")
        let ref = env.addIntake(on: "2026-07-18")

        env.metrics.revert(sourceRef: ref, at: env.clock.now)

        XCTAssertEqual(env.comebackGifts.count, 1)
        XCTAssertEqual(env.comebackGifts.first?.state, .ready)
    }

    func testNoMoreThanOncePerThirtyDays() {
        let env = GameEnv()
        env.addIntake(on: "2026-07-10")
        env.addIntake(on: "2026-07-14")        // подарунок №1
        env.addIntake(on: "2026-08-01")        // перерва, але ще 18 днів — без подарунка
        env.addIntake(on: "2026-08-14")        // 31 день від першого — знову можна
        XCTAssertEqual(env.comebackGifts.map { env.calendar.dayKey(for: $0.acquiredAt).rawValue }.sorted(),
                       ["2026-07-14", "2026-08-14"])
        XCTAssertEqual(env.game.lastComebackGiftAt().map { env.calendar.dayKey(for: $0).rawValue }, "2026-08-14")
    }
}

/// Б. «Знову в ритмі» — +25 XP за норму після пропуску, що обірвав серію ≥ 3 (§12.5 Б, критерій §19.17).
@MainActor
final class BounceBackTests: XCTestCase {

    private func bonusEntries(_ env: GameEnv) -> [XPEntry] {
        env.store.xpEntries(reason: .bounceBack).filter { $0.revertedAt == nil }
    }

    /// 14–16 норма, 17 пропущено, 18 норма.
    private func brokenStreakEnv() -> GameEnv {
        let env = GameEnv()
        for day in 14...16 { env.completeDay("2026-07-\(day)") }
        return env
    }

    func testGoalAfterMissedDayGivesBonus() {
        let env = brokenStreakEnv()
        _ = env.game.takeRecentUnlocks()

        env.completeDay("2026-07-18", hour: 15)

        XCTAssertEqual(bonusEntries(env).map(\.effectiveAmount), [25])
        XCTAssertEqual(env.game.takeRecentUnlocks().bounceBackXp, 25, "тост «Знову в ритмі»")
        XCTAssertEqual(env.game.lastBounceBackDay()?.rawValue, "2026-07-18")
    }

    func testShortStreakGivesNothing() {
        let env = GameEnv()
        for day in 15...16 { env.completeDay("2026-07-\(day)") }
        env.completeDay("2026-07-18")
        XCTAssertTrue(bonusEntries(env).isEmpty, "чергування «норма — пропуск — норма» не фармиться")
    }

    func testFrozenYesterdayGivesNothing() {
        let env = brokenStreakEnv()
        let prize = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!
        XCTAssertTrue(env.game.useFreeze(prizeId: prize.id), "заморожено вчора")

        env.completeDay("2026-07-18", hour: 15)

        XCTAssertTrue(bonusEntries(env).isEmpty, "заморозка вже врятувала ритм")
    }

    func testFreezingYesterdayAfterBonusRevertsIt() {
        let env = brokenStreakEnv()
        env.completeDay("2026-07-18", hour: 12)
        XCTAssertEqual(bonusEntries(env).count, 1)

        let prize = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!
        XCTAssertTrue(env.game.useFreeze(prizeId: prize.id))

        XCTAssertTrue(bonusEntries(env).isEmpty)
    }

    func testUndoRevertsAndRestoreAwardsAgain() {
        let env = brokenStreakEnv()
        env.completeDay("2026-07-18", hour: 12)
        let goalRef = DeterministicID.uuid(from: "day.goalMet:2026-07-18")

        env.metrics.revert(sourceRef: goalRef, at: env.clock.now)
        XCTAssertTrue(bonusEntries(env).isEmpty, "норму відкотили — бонус теж")

        env.metrics.record(MetricEvent(
            name: .dayGoalMet, value: 1, occurredAt: GameEnv.date(day: 18, hour: 13), sourceRef: goalRef
        ))
        XCTAssertEqual(bonusEntries(env).count, 1, "повернута порція повертає й бонус")
    }

    func testNoMoreThanOncePerSevenDays() {
        let env = GameEnv()
        for day in 4...6 { env.completeDay("2026-07-0\(day)") }
        env.completeDay("2026-07-08")                     // бонус №1 (7-ме пропущено)
        for day in 9...10 { env.completeDay("2026-07-\(day)") }
        env.completeDay("2026-07-12")                     // 11-те пропущено, але минуло 4 дні
        XCTAssertEqual(bonusEntries(env).map(\.dayKey), ["2026-07-08"])
    }

    /// Буст множить і цей XP (SPEC-PRIZES §7); множник серії `XPEngine` дає лише порціям.
    func testBoostDoublesTheBonus() {
        let env = brokenStreakEnv()
        let boost = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        XCTAssertTrue(env.game.activateBoost(prizeId: boost.id))

        env.completeDay("2026-07-18", hour: 15)

        XCTAssertEqual(bonusEntries(env).map(\.effectiveAmount), [50])
    }
}
