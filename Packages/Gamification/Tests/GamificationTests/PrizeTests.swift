import XCTest
import Core
import Persistence
import Metrics
@testable import Gamification

/// Модуль «Призи» (SPEC-PRIZES, WAT-34). Годинник — 18.07.2026, 14:00.
@MainActor
final class FreezeTargetTests: XCTestCase {

    // §6.2, п. 1
    func testYesterdayCountedTargetsToday() {
        let env = GameEnv()
        env.completeDay("2026-07-17")
        XCTAssertEqual(env.game.freezeTarget(), .today)
    }

    // §6.2, п. 2
    func testMissedYesterdayAfterStreakTargetsYesterday() {
        let env = GameEnv()
        for day in 12...16 { env.completeDay("2026-07-\(day)") }
        XCTAssertEqual(env.game.freezeTarget(), .yesterday(savedStreak: 5))
    }

    // §6.2, п. 3
    func testMissedYesterdayWithoutStreakTargetsToday() {
        let env = GameEnv()
        env.completeDay("2026-07-14")
        XCTAssertEqual(env.game.freezeTarget(), .today)
    }

    // §6.2, п. 4
    func testTodayAlreadyCountedDisablesFreeze() {
        let env = GameEnv()
        env.completeDay("2026-07-17")
        env.completeDay("2026-07-18")
        XCTAssertEqual(env.game.freezeTarget(), .todayAlreadyCounted)

        let prize = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!
        XCTAssertFalse(env.game.useFreeze(prizeId: prize.id), "заморозка не згоряє даремно")
        XCTAssertEqual(env.game.prizeInventory().ready.first?.count, 1)
    }

    /// Учора пропущено, але сьогодні норму вже закрито: учора досі можна врятувати.
    func testMissedYesterdayWinsOverClosedToday() {
        let env = GameEnv()
        env.completeDay("2026-07-16")
        env.completeDay("2026-07-18")
        XCTAssertEqual(env.game.freezeTarget(), .yesterday(savedStreak: 1))
    }
}

@MainActor
final class FreezeUseTests: XCTestCase {

    func testFreezingYesterdayKeepsStreakWithoutGrowing() {
        let env = GameEnv()
        for day in 12...16 { env.completeDay("2026-07-\(day)") }
        // `completeDay` перераховує серію на дату події — тут «зараз» уже 18-те.
        env.game.refresh(at: env.clock.now)
        XCTAssertEqual(env.game.streakSummary().current, 0, "учора пропущено — серія обірвалась")
        let prize = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!

        XCTAssertTrue(env.game.useFreeze(prizeId: prize.id))

        XCTAssertEqual(env.game.streakSummary().current, 5, "серія 5 збереглась, але не стала 6")
        XCTAssertFalse(
            env.game.prizeInventory().ready.contains { $0.oldest.id == prize.id },
            "використаний приз зникає"
        )
        XCTAssertEqual(env.game.prizes().first { $0.id == prize.id }?.state, .used)

        env.completeDay("2026-07-18")
        XCTAssertEqual(env.game.streakSummary().current, 6, "сьогоднішня норма продовжує врятовану серію")
    }

    /// Два пропущені дні поспіль закриваються двома заморозками по черзі (§6.2).
    func testSecondFreezeTargetsTodayAfterYesterdayIsFrozen() {
        let env = GameEnv()
        env.completeDay("2026-07-16")
        let first = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!
        let second = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!

        XCTAssertTrue(env.game.useFreeze(prizeId: first.id))
        XCTAssertEqual(env.game.freezeTarget(), .today)
        XCTAssertTrue(env.game.useFreeze(prizeId: second.id))
        XCTAssertEqual(env.game.freezeTarget(), .todayAlreadyCounted)
        XCTAssertEqual(env.game.streakSummary().current, 1)
    }

    /// Заморозили сьогодні, а ввечері таки закрили норму — приз повертається (§6.3).
    func testFreezeReturnsWhenFrozenDayIsCompleted() {
        let env = GameEnv()
        env.completeDay("2026-07-17")
        let prize = env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)!
        XCTAssertTrue(env.game.useFreeze(prizeId: prize.id))
        XCTAssertEqual(env.game.streakSummary().freezeTokens, 0)

        env.completeDay("2026-07-18", hour: 20)

        XCTAssertEqual(env.game.prizes().first { $0.id == prize.id }?.state, .ready, "приз знову в інвентарі")
        XCTAssertEqual(env.game.streakSummary().freezeTokens, 1)
        XCTAssertEqual(env.game.streakSummary().current, 2, "день рахується як виконаний, а не заморожений")
        XCTAssertFalse(env.store.streakState().frozenDayKeys.contains("2026-07-18"))

        // Повернутий предмет можна використати знову — метрика активації не блокує.
        env.clock.advance(by: 86_400)
        XCTAssertTrue(env.game.useFreeze(prizeId: prize.id))
    }

    func testBoostPrizeCannotBeUsedAsFreeze() {
        let env = GameEnv()
        let boost = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        XCTAssertFalse(env.game.useFreeze(prizeId: boost.id))
    }
}

@MainActor
final class BoostTests: XCTestCase {

    private func intakeEntries(_ env: GameEnv) -> [XPEntry] {
        env.store.xpEntries(dayKey: "2026-07-18").filter { $0.reason == .intake && $0.revertedAt == nil }
    }

    func testBoostLastsUntilLocalMidnight() {
        let env = GameEnv()
        let prize = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!

        XCTAssertTrue(env.game.activateBoost(prizeId: prize.id))

        let active = env.game.prizeInventory().active
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.expiresAt, GameEnv.date(day: 19, hour: 0), "до 00:00, а не +24 год")
        XCTAssertEqual(active.first?.remaining(at: env.clock.now), 10 * 3600)
        XCTAssertEqual(active.first?.remainingFraction(at: env.clock.now), 1)
    }

    func testBoostDoublesXPAndMultipliesWithStreak() {
        let env = GameEnv()
        for day in 15...17 { env.completeDay("2026-07-\(day)") }
        env.addIntakeEvent(200, hour: 9)
        let plain = intakeEntries(env).first!.multiplier

        let prize = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        env.game.activateBoost(prizeId: prize.id)
        env.addIntakeEvent(200, hour: 15)

        let boosted = intakeEntries(env).max { $0.createdAt < $1.createdAt }!
        XCTAssertEqual(plain, env.game.xp.rules.multiplier(streak: 3), accuracy: 0.0001)
        XCTAssertEqual(boosted.multiplier, plain * 2, accuracy: 0.0001, "серія × 2")
    }

    func testBoostMultipliesNonIntakeXPToo() {
        let env = GameEnv()
        let prize = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        env.game.activateBoost(prizeId: prize.id)

        env.completeDay("2026-07-18", hour: 16)

        let goal = env.store.xpEntries(dayKey: "2026-07-18").first { $0.reason == .dailyGoal }!
        XCTAssertEqual(goal.multiplier, 2)
    }

    func testOnlyOneBoostAtATime() {
        let env = GameEnv()
        let first = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        let second = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!

        XCTAssertTrue(env.game.activateBoost(prizeId: first.id))
        XCTAssertFalse(env.game.activateBoost(prizeId: second.id), "черги бустів немає")
        XCTAssertFalse(env.game.activateBoost(prizeId: first.id), "повторно не вмикається")
    }

    func testBoostExpiresAtMidnightWithoutBackgroundWork() {
        let env = GameEnv()
        let prize = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        env.game.activateBoost(prizeId: prize.id)

        env.clock.set(GameEnv.date(day: 19, hour: 0))

        XCTAssertTrue(env.game.prizeInventory().isEmpty, "прострочений буст зникає з UI")
        XCTAssertEqual(env.game.prizes().first?.state, .expired)
        XCTAssertEqual(env.game.xp.boostMultiplier(at: env.clock.now), 1)
    }

    func testUndoRevertsBoostedXPButKeepsBoost() {
        let env = GameEnv()
        let prize = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        env.game.activateBoost(prizeId: prize.id)
        let before = env.game.levelProgress().totalXp

        let ref = env.addIntakeEvent(200, hour: 15)
        XCTAssertGreaterThan(env.game.levelProgress().totalXp, before)
        env.metrics.revert(sourceRef: ref, at: env.clock.now)

        XCTAssertEqual(env.game.levelProgress().totalXp, before)
        XCTAssertEqual(env.game.prizeInventory().active.count, 1, "сам буст не відкочується")
    }
}

@MainActor
final class PrizeInventoryTests: XCTestCase {

    func testIdenticalPrizesStackOldestFirstFreezeOnTop() {
        let env = GameEnv()
        let boost = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed, at: GameEnv.date(day: 10, hour: 9))!
        env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed, at: GameEnv.date(day: 12, hour: 9))
        env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)

        let ready = env.game.prizeInventory().ready

        XCTAssertEqual(ready.map(\.key), [RewardCatalog.freezeKey, RewardCatalog.boostKey])
        XCTAssertEqual(ready.map(\.count), [1, 2])
        XCTAssertEqual(ready.last?.oldest.id, boost.id, "стос використовує найстаріший предмет")
        XCTAssertNotNil(ready.first?.freezeTarget)
        XCTAssertNil(ready.last?.freezeTarget)
    }

    func testRetiredKeysAreHidden() {
        let env = GameEnv()
        for key in ["badge.hydration", "quests.weekly", "theme.ocean", "xp.streakBonus"] {
            env.store.insertReward(RewardItem(defKey: key, source: .level, acquiredAt: env.clock.now))
        }
        env.store.save()
        XCTAssertTrue(env.game.prizeInventory().isEmpty)
    }

    func testNewDotClearsPerStackAndForAll() {
        let env = GameEnv()
        env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        XCTAssertTrue(env.game.prizeInventory().ready.allSatisfy(\.isNew))

        env.game.markPrizesSeen(key: RewardCatalog.freezeKey)
        XCTAssertEqual(env.game.prizeInventory().ready.map(\.isNew), [false, true])
        XCTAssertTrue(env.game.hasUnseenPrizes)

        env.game.markPrizesSeen()
        XCTAssertFalse(env.game.hasUnseenPrizes)
    }

    func testLevelGrantsOnePrizePerLevel() {
        let env = GameEnv()
        for index in 0..<60 { env.addIntakeEvent(150, hour: 8 + index % 12) }
        let level = env.game.levelProgress().level
        XCTAssertGreaterThanOrEqual(level, 3)

        let prizes = env.game.prizes()
        XCTAssertEqual(prizes.count, level - 1, "рівні 2…N — по одному призу")
        XCTAssertEqual(prizes.filter { $0.key == RewardCatalog.freezeKey }.count, level / 3)
    }
}
