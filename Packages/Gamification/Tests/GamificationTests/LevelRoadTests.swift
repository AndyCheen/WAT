import XCTest
import Core
import Persistence
import Metrics
@testable import Gamification

/// Шлях рівнів — SPEC-PRIZES §16 (WAT-44). Годинник — 18.07.2026, 14:00.
@MainActor
final class LevelRoadCatalogTests: XCTestCase {

    /// Таблиця §16.1 дослівно: правка, що її ламає, змінює баланс, погоджений у ТЗ.
    func testNodeTable() {
        XCTAssertNil(LevelRoadCatalog.node(forLevel: 1), "старт без призу")
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 2), .prize(.boost))
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 4), .choice([.freeze, .boost]))
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 6), .mystery(.regular))
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 8), .prize(.freeze))
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 10), .mystery(.grand))
        for odd in [3, 5, 7, 9] {
            XCTAssertNil(LevelRoadCatalog.node(forLevel: odd), "до 10-го — приз через рівень")
        }

        let cycle: [LevelNode] = [.prize(.boost), .choice([.freeze, .boost]), .prize(.boost), .prize(.freeze)]
        for start in [11, 16, 21, 26] {
            XCTAssertEqual((0..<4).map { LevelRoadCatalog.node(forLevel: start + $0) }, cycle)
        }
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 15), .mystery(.regular))
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 20), .mystery(.grand), "кожен 10-й — великий")
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 25), .mystery(.regular))
        XCTAssertEqual(LevelRoadCatalog.node(forLevel: 30), .mystery(.grand))
        XCTAssertTrue((11...60).allSatisfy { LevelRoadCatalog.node(forLevel: $0) != nil }, "з 11-го — на кожному")
    }

    func testNextRewardLevelSkipsEmptyLevels() {
        XCTAssertEqual(LevelRoadCatalog.nextRewardLevel(after: 1), 2)
        XCTAssertEqual(LevelRoadCatalog.nextRewardLevel(after: 2), 4)
        XCTAssertEqual(LevelRoadCatalog.nextRewardLevel(after: 9), 10)
        XCTAssertEqual(LevelRoadCatalog.nextRewardLevel(after: 12), 13)
    }

    func testPoolsAreHundredPercent() {
        XCTAssertEqual(MysteryPool.regular.totalWeight, 100)
        XCTAssertEqual(MysteryPool.grand.totalWeight, 100)
    }

    /// Великий — ювілей: жодного одного простого призу.
    func testGrandPoolNeverGivesSinglePlainPrize() {
        for entry in MysteryPool.grand.entries {
            let items = entry.grants.reduce(0) { $0 + $1.count }
            XCTAssertTrue(items >= 2 || entry.grants == [.triple], "\(entry.grants)")
        }
    }

    func testRollIsDeterministic() {
        let a = MysteryRoll.outcome(level: 6, seed: "42", pool: .regular)
        XCTAssertEqual(MysteryRoll.outcome(level: 6, seed: "42", pool: .regular), a)
    }

    /// Частоти на 10 000 зерен — у межах ±2 п. п. від ваг §16.2.
    func testRollFollowsWeights() {
        for pool in [MysteryPool.regular, .grand] {
            var counts = [Int](repeating: 0, count: pool.entries.count)
            let runs = 10_000
            for seed in 0..<runs {
                let grants = MysteryRoll.outcome(level: 6, seed: "\(seed)", pool: pool)
                counts[pool.entries.firstIndex { $0.grants == grants }!] += 1
            }
            for (entry, count) in zip(pool.entries, counts) {
                XCTAssertEqual(Double(count) / Double(runs) * 100, Double(entry.weight), accuracy: 2, "\(entry.grants)")
            }
        }
    }
}

@MainActor
final class LevelRoadServiceTests: XCTestCase {

    func testChoiceWaitsForPickAndIsFinal() {
        let env = GameEnv()
        env.reachLevel(4)
        XCTAssertEqual(env.game.levelRoad().pending.map(\.level), [4])

        XCTAssertFalse(env.game.claimChoice(level: 4, key: RewardCatalog.tripleKey), "такого варіанта у вузлі немає")
        XCTAssertTrue(env.game.claimChoice(level: 4, key: RewardCatalog.freezeKey))
        XCTAssertFalse(env.game.claimChoice(level: 4, key: RewardCatalog.boostKey), "вибір остаточний")

        let node = env.game.levelRoad().nodes.first { $0.level == 4 }!
        XCTAssertEqual(node.status, .claimed)
        XCTAssertEqual(node.claimKind, .choice)
        XCTAssertEqual(node.claimed, [.freeze])
        XCTAssertEqual(env.game.prizes().filter { $0.key == RewardCatalog.freezeKey }.count, 1)
        XCTAssertTrue(env.game.levelRoad().pending.isEmpty)
    }

    func testCannotClaimAheadOfLevel() {
        let env = GameEnv()
        env.reachLevel(3)
        XCTAssertFalse(env.game.claimChoice(level: 4, key: RewardCatalog.freezeKey))
        XCTAssertNil(env.game.openMystery(level: 6))
    }

    func testMysteryOpensOnceWithPredeterminedContent() {
        let env = GameEnv()
        env.reachLevel(6)
        let expected = MysteryRoll.outcome(level: 6, seed: env.game.mysterySeed, pool: .regular)

        let grants = env.game.openMystery(level: 6)
        XCTAssertEqual(grants, expected, "вміст визначений наперед")
        XCTAssertNil(env.game.openMystery(level: 6), "двічі не відкривається")

        let items = env.store.rewardItems().filter { $0.acquiredByRef == GamificationService.levelNodeRef(6) }
        XCTAssertEqual(items.count, expected.reduce(0) { $0 + $1.count }, "набір кладе стільки предметів, скільки в ньому")
        XCTAssertEqual(env.game.levelRoad().nodes.first { $0.level == 6 }?.claimKind, .mystery)
    }

    /// До WAT-44 на 4-му рівні лежав звичайний ⚡ — дев-дані не мають отримати ще й вибір.
    func testLegacyPrizeCountsAsClaimed() {
        let env = GameEnv()
        env.reachLevel(4)
        env.store.insertReward(RewardItem(
            defKey: RewardCatalog.boostKey, source: .level, acquiredAt: env.clock.now,
            acquiredByRef: GamificationService.levelPrizeRef(4, key: RewardCatalog.boostKey)
        ))
        env.store.save()

        XCTAssertTrue(env.game.levelRoad().pending.isEmpty)
        XCTAssertFalse(env.game.claimChoice(level: 4, key: RewardCatalog.freezeKey))
    }

    /// До WAT-44 на 8-му рівні був ⚡, тепер там 🧊: рівень, де вже є приз, другого не отримує.
    func testLegacyPlainPrizeIsNotGrantedTwice() {
        let env = GameEnv()
        env.store.insertReward(RewardItem(
            defKey: RewardCatalog.boostKey, source: .level, acquiredAt: env.clock.now,
            acquiredByRef: GamificationService.levelPrizeRef(8, key: RewardCatalog.boostKey)
        ))
        env.store.save()
        env.reachLevel(8)

        let level8 = env.store.rewardItems().filter { GamificationService.levelRefs(8).contains($0.acquiredByRef ?? UUID()) }
        XCTAssertEqual(level8.map(\.defKey), [RewardCatalog.boostKey])
    }

    /// Виданий приз не відкликається (§3.4), а вузол вище рівня просто перестає чекати.
    func testLevelRevertKeepsClaimedPrize() {
        let env = GameEnv()
        let ref = UUID()
        env.game.xp.award(amount: LevelCalculator.totalXpRequired(forLevel: 4, curve: env.game.xp.curve),
                          reason: .questCompleted, refId: ref, at: env.clock.now)
        XCTAssertTrue(env.game.claimChoice(level: 4, key: RewardCatalog.boostKey))

        env.game.xp.revert(refId: ref, at: env.clock.now)

        XCTAssertEqual(env.game.levelProgress().level, 1)
        XCTAssertEqual(env.game.prizes().filter { $0.key == RewardCatalog.boostKey }.count, 1)
        XCTAssertTrue(env.game.levelRoad().pending.isEmpty)
    }

    func testHorizonShowsThreeRewardsAndTwoInFog() {
        let env = GameEnv()
        env.reachLevel(9)
        let road = env.game.levelRoad()
        let ahead = road.nodes.filter { $0.level > 9 }

        XCTAssertEqual(ahead.filter { $0.status == .upcoming }.map(\.level), [10, 11, 12])
        XCTAssertEqual(ahead.filter { $0.status == .fogged }.map(\.level), [13, 14])
        XCTAssertEqual(road.nodes.last?.level, 14)
        XCTAssertEqual(road.nodes.first?.level, 1, "минуле — все")
        XCTAssertEqual(road.nextReward?.level, 10)
    }

    func testEmptyLevelsBeforeAndAfterTheThirdReward() {
        let env = GameEnv()
        env.reachLevel(2)
        let statuses = Dictionary(uniqueKeysWithValues: env.game.levelRoad().nodes.map { ($0.level, $0.status) })
        // Попереду: 4, 6, 8 — повністю; 3, 5, 7 — порожні до туману; 9 і далі — туман до 10-го і 11-го призів.
        XCTAssertEqual(statuses[3], .ahead)
        XCTAssertEqual(statuses[8], .upcoming)
        XCTAssertEqual(statuses[9], .fogged)
        XCTAssertEqual(statuses[10], .fogged)
        XCTAssertEqual(statuses[11], .fogged)
        XCTAssertNil(statuses[12])
    }

    func testFocusPrefersPendingThenLastClaimed() {
        let env = GameEnv()
        XCTAssertEqual(env.game.levelRoad().focusLevel, 1, "нічого немає — поточний рівень")

        env.reachLevel(7)
        XCTAssertEqual(env.game.levelRoad().focusLevel, 4, "найраніший, що чекає дії")

        env.game.claimChoice(level: 4, key: RewardCatalog.boostKey)
        XCTAssertEqual(env.game.levelRoad().focusLevel, 6)

        env.game.openMystery(level: 6)
        XCTAssertEqual(env.game.levelRoad().focusLevel, 6, "останній отриманий приз")
    }
}

/// 🌟 «Потрійний XP» (SPEC-PRIZES §16.2).
@MainActor
final class TripleBoostTests: XCTestCase {

    func testTripleMultipliesWithStreak() {
        let env = GameEnv()
        for day in 15...17 { env.completeDay("2026-07-\(day)") }
        let prize = env.game.grantPrize(key: RewardCatalog.tripleKey, source: .seed)!
        XCTAssertTrue(env.game.activateBoost(prizeId: prize.id))

        env.addIntakeEvent(250, hour: 15)

        let entry = env.store.xpEntries(dayKey: "2026-07-18").first { $0.reason == .intake }!
        XCTAssertEqual(entry.multiplier, env.game.xp.rules.multiplier(streak: 3) * 3, accuracy: 0.0001)
    }

    func testDoubleAndTripleDoNotStack() {
        let env = GameEnv()
        let double = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        let triple = env.game.grantPrize(key: RewardCatalog.tripleKey, source: .seed)!

        XCTAssertTrue(env.game.activateBoost(prizeId: triple.id))
        XCTAssertFalse(env.game.activateBoost(prizeId: double.id), "одночасно діє один буст, будь-який")
        XCTAssertEqual(env.game.xp.boostMultiplier(at: env.clock.now), 3)
    }

    func testInventoryOrderFreezeTripleBoost() {
        let env = GameEnv()
        for key in [RewardCatalog.boostKey, RewardCatalog.tripleKey, RewardCatalog.freezeKey] {
            env.game.grantPrize(key: key, source: .seed)
        }
        XCTAssertEqual(env.game.prizeInventory().ready.map(\.key),
                       [RewardCatalog.freezeKey, RewardCatalog.tripleKey, RewardCatalog.boostKey])
    }
}

/// XP за воду — за об'єм, і баланс із конфігурації (SPEC-PRIZES §16.13).
@MainActor
final class WaterXPTests: XCTestCase {

    private func intakeXp(_ env: GameEnv) -> Int {
        env.store.xpEntries(dayKey: "2026-07-18")
            .filter { $0.reason == .intake && $0.revertedAt == nil }
            .reduce(0) { $0 + $1.effectiveAmount }
    }

    func testFiveSmallPortionsEqualOneBig() {
        let small = GameEnv()
        for minute in 0..<5 { small.addIntake(50, hour: 10, minute: minute * 5) }
        let big = GameEnv()
        big.addIntake(250, hour: 10)

        XCTAssertEqual(intakeXp(small), 5)
        XCTAssertEqual(intakeXp(big), 5)
    }

    func testFractionsAccumulateWithinTheDay() {
        let env = GameEnv()
        env.addIntake(200, hour: 9)   // 4 XP (⌊200·5/250⌋)
        env.addIntake(100, hour: 10)  // 300 мл → 6, приріст 2
        XCTAssertEqual(intakeXp(env), 6)
    }

    /// Понад стелю 120 % XP за воду не нараховується.
    func testNoWaterXpAboveCap() {
        let env = GameEnv()
        env.addIntake(2000, hour: 9)
        env.addIntake(400, hour: 12)   // 2400 — рівно стеля
        let atCap = intakeXp(env)
        env.addIntake(500, hour: 15)

        XCTAssertEqual(atCap, 48)
        XCTAssertEqual(intakeXp(env), atCap, "понад 2400 мл — 0 XP")
    }

    func testUndoRevertsPortionXp() {
        let env = GameEnv()
        env.addIntake(250, hour: 9)
        let id = env.addIntake(500, hour: 10)
        env.removeIntake(id)
        XCTAssertEqual(intakeXp(env), 5)
    }

    func testGlobalMultiplierScalesAllXp() {
        let env = GameEnv()
        env.game.xp.rules = env.game.xp.rules.applyingBalance([XPRules.BalanceKey.xpMultiplier: "2"])

        env.addIntake(250, hour: 9)
        env.completeDay("2026-07-18", hour: 16)

        let entries = env.store.xpEntries(dayKey: "2026-07-18").filter { $0.revertedAt == nil }
        XCTAssertEqual(entries.first { $0.reason == .intake }?.effectiveAmount, 10)
        XCTAssertEqual(entries.first { $0.reason == .dailyGoal }?.effectiveAmount, 100)
    }

    func testBalanceParsing() {
        let rules = XPRules.default.applyingBalance([
            XPRules.BalanceKey.xpPerVolumeStep: "10",
            XPRules.BalanceKey.volumeStepMl: " 200 ",
            XPRules.BalanceKey.xpMultiplier: "1,5"
        ])
        XCTAssertEqual(rules.xpPerVolumeStep, 10)
        XCTAssertEqual(rules.volumeStepMl, 200)
        XCTAssertEqual(rules.xpMultiplier, 1.5)
        XCTAssertEqual(rules.waterXp(countedBefore: 0, countedAfter: 500), 25)
    }

    /// Зламаний конфіг не обнуляє XP: нечислове, ≤ 0 і нерозкрита змінна збірки лишають типове.
    func testInvalidBalanceKeepsDefaults() {
        let rules = XPRules.default.applyingBalance([
            XPRules.BalanceKey.xpPerVolumeStep: "$(WT_XP_PER_VOLUME_STEP)",
            XPRules.BalanceKey.volumeStepMl: "0",
            XPRules.BalanceKey.xpMultiplier: "abc"
        ])
        XCTAssertEqual(rules, .default)
    }
}

/// Призи у звіті місяця (SPEC-PRIZES §16.16).
@MainActor
final class PeriodPrizeTests: XCTestCase {
    func testPeriodSummaryCountsReceivedPrizes() {
        let env = GameEnv()
        env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        env.game.grantPrize(key: RewardCatalog.freezeKey, source: .seed, at: GameEnv.date(day: 2, hour: 10, month: 6))

        let july = (1...31).map { DayKey(rawValue: String(format: "2026-07-%02d", $0)) }
        XCTAssertEqual(env.game.periodSummary(days: july).prizesReceived, 1, "червневий приз у липневий звіт не йде")
    }
}
