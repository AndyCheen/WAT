import XCTest
import Core
import Persistence
import Metrics
@testable import Gamification

/// Рушій завдань на справжній базі: тижневі з дня видачі, прострочення, архівні ключі, XP з інстансу (QUESTS-PLAN §1.8).
@MainActor
final class QuestEngineTests: XCTestCase {
    /// Тижневе рахує дні лише від дня видачі: ціль уже підігнана під дні, що лишились (§5.7).
    func testWeeklyCountsFromAssignedDay() {
        let env = GameEnv(day: 15, hour: 8, quests: QuestForcing(weekly: [("weekly.goalDays", 2)]))
        env.goalDay("2026-07-13")
        env.goalDay("2026-07-14")
        XCTAssertEqual(env.game.weeklyQuests().first?.progress, 0, "пн і вт — до видачі в середу")

        env.clock.set(GameEnv.date("2026-07-16", hour: 20))
        env.goalDay("2026-07-15")
        env.goalDay("2026-07-16")
        let quest = env.game.weeklyQuests().first!
        XCTAssertEqual(quest.progress, 2)
        XCTAssertTrue(quest.isDone)
        XCTAssertEqual(quest.kind, .days)
    }

    /// Прострочене невиконане зникає з дошки й не відкривається знову — ні часом, ні поверненою порцією.
    func testOverdueDisappearsAndNeverReopens() {
        let env = GameEnv(day: 18, hour: 8, quests: QuestForcing(daily: ["daily.wakeGlass", "daily.glasses"]))
        let wake = env.game.dailyQuests().first { $0.key == "daily.wakeGlass" }!
        XCTAssertEqual(wake.deadlineMinute, 9 * 60)
        XCTAssertEqual(wake.deadline, GameEnv.date(day: 18, hour: 9))

        XCTAssertEqual(env.game.questBoard().expiredDaily, 0)
        env.clock.set(GameEnv.date(day: 18, hour: 9, minute: 30))
        XCTAssertEqual(env.game.dailyQuests().map(\.key), ["daily.glasses"], "дедлайн минув — рядка немає")
        XCTAssertEqual(env.game.questBoard().expiredDaily, 1, "ще активне з минулим дедлайном — уже прострочене")
        env.game.refresh(at: env.clock.now)
        XCTAssertEqual(env.game.questBoard().expiredDaily, 1, "і після позначки `.expired`")
        XCTAssertEqual(env.store.quests(scope: .daily, periodKey: "2026-07-18")
            .first { $0.defKey == "daily.wakeGlass" }?.state, .expired)

        env.addIntake(250, hour: 8, minute: 30)
        XCTAssertNil(env.game.dailyQuests().first { $0.key == "daily.wakeGlass" }, "прострочене не оживає")
        XCTAssertTrue(env.metrics.events(.questCompleted).isEmpty)
    }

    /// Виконане до T і відкочене вже після T — знову відкрите, але одразу прострочене: на екран не повертається.
    func testRevertAfterDeadlineExpires() {
        let env = GameEnv(day: 18, hour: 8, quests: QuestForcing(daily: ["daily.wakeGlass"]))
        let glass = env.addIntake(250, hour: 8, minute: 20)
        XCTAssertTrue(env.game.dailyQuests().first!.isDone)

        env.clock.set(GameEnv.date(day: 18, hour: 10))
        env.removeIntake(glass)
        XCTAssertTrue(env.game.dailyQuests().isEmpty)
        XCTAssertEqual(env.game.questBoard().expiredDaily, 1, "«Усе на сьогодні» тут не про що")
        XCTAssertEqual(env.game.levelProgress().totalXp, 0, "XP за воду й за завдання відкочено")
    }

    /// Архівний інстанс дня оновлення доживає свій день з тим самим XP, і нових поверх нього не видаємо (§3.7).
    func testRetiredInstanceLivesOut() {
        let env = GameEnv(quests: nil)
        let legacy = QuestInstance(defKey: "daily.goal", periodKey: "2026-07-19", target: 2000,
                                   assignedAt: GameEnv.date(day: 19, hour: 0))
        env.store.insertQuest(legacy)
        env.store.save()

        env.clock.set(GameEnv.date(day: 19, hour: 20))
        env.drink(2000, on: "2026-07-19", hour: 12)
        let daily = env.game.dailyQuests()
        XCTAssertEqual(daily.map(\.key), ["daily.goal"])
        XCTAssertTrue(daily[0].isDone)
        XCTAssertEqual(daily[0].rewardXp, 25)
        XCTAssertEqual(env.store.xpEntries(refId: legacy.id).first?.amount, 25)
    }

    /// XP фіксується на інстансі: перебалансування не змінює виданого. Буст множить, серія — ні (§8).
    func testXpFromInstanceBoostedButNotByStreak() {
        let env = GameEnv(day: 18, hour: 8, quests: QuestForcing(daily: ["starter.firstGoal"]))
        for day in 14...17 { env.goalDay("2026-07-\(day)") }
        env.game.xp.rules.dailyQuestXp = [100, 200, 300]
        let boost = env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed)!
        XCTAssertTrue(env.game.activateBoost(prizeId: boost.id))

        env.drink(2000, on: "2026-07-18", hour: 12)
        let quest = env.store.quests(scope: .daily, periodKey: "2026-07-18").first!
        XCTAssertEqual(quest.rewardXp, 25)
        let entry = env.store.xpEntries(refId: quest.id).first!
        XCTAssertEqual(entry.amount, 25)
        XCTAssertEqual(entry.multiplier, 2, "буст ×2, серія 4 дні — ні")
    }

    /// Д4 відкривається подією `day.goalAhead`, що приходить після «норму закрито».
    func testGoalWithoutRemindersWaitsForGoalAhead() {
        let env = GameEnv(day: 18, hour: 8, quests: QuestForcing(daily: ["daily.goalNoReminders"]))
        env.drink(2000, on: "2026-07-18", hour: 12)
        XCTAssertFalse(env.game.dailyQuests().first!.isDone, "норма є, але без `day.goalAhead`")
        env.metrics.record(MetricEvent(name: .dayGoalAhead, value: 1, occurredAt: GameEnv.date(day: 18, hour: 12),
                                       sourceRef: UUID()))
        env.metrics.commit()
        XCTAssertTrue(env.game.dailyQuests().first!.isDone)
    }

    func testForcingArgument() {
        let forcing = QuestForcing(argument: "daily:daily.wakeGlass,daily.glasses,nope;weekly:weekly.goalDays=5,weekly.wakeGlassDays")
        XCTAssertEqual(forcing?.daily, ["daily.wakeGlass", "daily.glasses"])
        XCTAssertEqual(forcing?.weekly.map(\.key), ["weekly.goalDays", "weekly.wakeGlassDays"])
        XCTAssertEqual(forcing?.weekly.map(\.count), [5, nil])
        XCTAssertNil(QuestForcing(argument: "daily:nope"))
    }

    // MARK: - Несподівані (SPEC-QUESTS §6, WAT-65)

    private func surpriseEnv(_ key: String, at minute: Int, hour: Int = 8) -> GameEnv {
        GameEnv(day: 18, hour: hour, quests: QuestForcing(surprise: (key, minute)))
    }

    private func surpriseInstance(_ env: GameEnv) -> QuestInstance? {
        env.store.quests(scope: .adhoc, periodKey: "adhoc:2026-07-18").first
    }

    /// ⚡ саме за завдання: рівні, підняті досягненнями, дають свої призи.
    private func boosts(_ env: GameEnv) -> Int {
        env.store.rewardItems(defKey: RewardCatalog.boostKey).filter { $0.source == .quest }.count
    }

    func testSurpriseIsInvisibleUntilItAppears() {
        let env = surpriseEnv("surprise.flash", at: 16 * 60)
        let surprise = env.game.questBoard().surprise
        XCTAssertEqual(surprise?.visibleFrom, GameEnv.date(day: 18, hour: 16))
        XCTAssertEqual(surprise?.deadline, GameEnv.date(day: 18, hour: 16, minute: 15))
        XCTAssertFalse(surprise!.isVisible(at: env.clock.now), "у дошці наперед — для таймлайна й сповіщення")
        XCTAssertTrue(surprise!.isVisible(at: GameEnv.date(day: 18, hour: 16, minute: 1)))
        XCTAssertFalse(surprise!.isVisible(at: GameEnv.date(day: 18, hour: 16, minute: 15)))
        XCTAssertTrue(env.game.dailyQuests().isEmpty, "несподіване — не щоденне")
        XCTAssertEqual(surprise?.rewardXp, 25)
        XCTAssertEqual(surprise?.kind, .volume)
        XCTAssertEqual(surprise?.progress, 0, "до появи прогрес не рахується")
    }

    func testPortionsBeforeAppearanceDoNotCount() {
        let env = surpriseEnv("surprise.flash", at: 16 * 60)
        env.clock.set(GameEnv.date(day: 18, hour: 15, minute: 50))
        env.addIntake(250, hour: 15, minute: 50)
        XCTAssertEqual(surpriseInstance(env)?.state, .active, "норму не закрито — не скасовується")

        env.clock.set(GameEnv.date(day: 18, hour: 16, minute: 5))
        env.addIntake(100, hour: 16, minute: 5)
        XCTAssertEqual(env.game.questBoard().surprise?.progress, 100, "порція о 15:50 — до появи")
        XCTAssertFalse(env.game.questBoard().surprise!.isDone)

        env.addIntake(50, hour: 16, minute: 6)
        let done = env.game.questBoard().surprise!
        XCTAssertTrue(done.isDone)
        XCTAssertEqual(env.metrics.events(.surpriseQuestCompleted).count, 1)
        XCTAssertEqual(boosts(env), 1, "⚡ у призах")
        XCTAssertTrue(env.isUnlocked("quest.firstSurprise"), "«Несподіванка»")
        XCTAssertEqual(env.store.xpEntries(refId: done.id).first?.amount, 25)
    }

    func testCancelledBeforeAppearanceByClosedGoal() {
        let env = surpriseEnv("surprise.flash", at: 16 * 60)
        env.clock.set(GameEnv.date(day: 18, hour: 12))
        env.drink(2000, on: "2026-07-18", hour: 12)
        XCTAssertEqual(surpriseInstance(env)?.state, .cancelled, "скасоване — не проігнороване (§6.4)")
        XCTAssertNil(env.game.questBoard().surprise)
    }

    /// Н1: частина вже йде за темпом — випито в блоці не менше, ніж крива чекає до появи.
    func testGlassNowCancelledWhenBlockIsOnPace() {
        let env = surpriseEnv("surprise.glassNow", at: 13 * 60 + 30)
        let block = env.game.questBoard().surprise!.blockIndex!
        let from = env.profiles.profile().schedule(isWeekend: true).curve(goalMl: 2000).goalBlocks()[block].fromMinute
        env.clock.set(GameEnv.date(day: 18, hour: 13, minute: 25))
        env.addIntake(50, hour: from / 60, minute: from % 60 + 5)
        XCTAssertEqual(surpriseInstance(env)?.state, .active, "50 мл — ще позаду кривої")
        env.addIntake(400, hour: 13, minute: 25)
        XCTAssertEqual(surpriseInstance(env)?.state, .cancelled)
    }

    func testExpiredIsIgnoredAndHidden() {
        let env = surpriseEnv("surprise.flash", at: 16 * 60)
        env.clock.set(GameEnv.date(day: 18, hour: 16, minute: 20))
        env.game.refresh(at: env.clock.now)
        XCTAssertEqual(surpriseInstance(env)?.state, .expired)
        XCTAssertNil(env.game.questBoard().surprise)
        XCTAssertEqual(boosts(env), 0)
    }

    /// ⚡ один на інстанс навіть після «відкат → знову виконано»; XP і подія відкочуються, приз — ні (§6.5).
    func testBoostOncePerInstanceAcrossUndo() {
        let env = surpriseEnv("surprise.flash", at: 16 * 60)
        env.clock.set(GameEnv.date(day: 18, hour: 16, minute: 5))
        let glass = env.addIntake(250, hour: 16, minute: 5)
        let id = surpriseInstance(env)!.id
        XCTAssertEqual(boosts(env), 1)

        env.removeIntake(glass)
        XCTAssertEqual(surpriseInstance(env)?.state, .active)
        XCTAssertTrue(env.store.xpEntries(refId: id).allSatisfy { $0.revertedAt != nil }, "XP за завдання відкочено")
        XCTAssertTrue(env.metrics.events(.surpriseQuestCompleted).isEmpty, "подію шини теж")
        XCTAssertEqual(boosts(env), 1, "виданий приз не відкликається")

        env.restoreIntake(glass)
        XCTAssertTrue(env.game.questBoard().surprise!.isDone)
        XCTAssertEqual(boosts(env), 1, "і вдруге не видається")
    }

    func testNoSurpriseUnderForcingWithoutIt() {
        let env = GameEnv(day: 18, hour: 8, quests: QuestForcing(daily: ["daily.glasses"]))
        XCTAssertNil(env.game.questBoard().surprise)
        XCTAssertTrue(env.store.quests(scope: .adhoc, periodKey: nil).isEmpty)
    }

    func testSurpriseForcingArgument() {
        let forcing = QuestForcing(argument: "surprise:surprise.glassNow@13:30")
        XCTAssertEqual(forcing?.surprise?.key, "surprise.glassNow")
        XCTAssertEqual(forcing?.surprise?.minute, 13 * 60 + 30)
        XCTAssertTrue(forcing?.daily.isEmpty ?? false)
        XCTAssertNil(QuestForcing(argument: "surprise:daily.glasses@13:30"), "лише несподівані")
        XCTAssertNil(QuestForcing(argument: "surprise:surprise.flash"), "без хвилини")
    }
}
