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
}
