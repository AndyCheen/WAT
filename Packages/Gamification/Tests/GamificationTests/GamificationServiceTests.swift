import XCTest
import Core
import Metrics
import Persistence
@testable import Gamification

@MainActor
final class GamificationServiceTests: XCTestCase {

    func testIntakeAwardsXP() {
        let env = GameEnv()
        env.addIntakeEvent(300)

        // 5 XP за порцію + 25 XP за досягнення «Перша крапля»
        XCTAssertEqual(env.game.levelProgress().totalXp, XPRules.default.perIntake + 25)
    }

    func testUndoOfIntakeReturnsXP() {
        let env = GameEnv()
        let ref = env.addIntakeEvent(300)
        XCTAssertEqual(env.game.levelProgress().totalXp, 30)

        env.metrics.revert(sourceRef: ref, at: env.clock.now)

        XCTAssertEqual(env.game.levelProgress().totalXp, 0, "відкат дії повертає досвід (ТЗ §5.2)")
    }

    func testDailyGoalAwardsBonusXP() {
        let env = GameEnv()
        env.completeDay("2026-07-18")

        // 50 XP за норму дня + 25 XP за щоденне завдання «Випити денну норму»
        XCTAssertGreaterThanOrEqual(env.game.levelProgress().totalXp, 50)
    }

    func testFirstDropAchievementUnlocks() {
        let env = GameEnv()
        XCTAssertFalse(env.game.achievementSnapshots().first { $0.key == "first.drop" }!.isUnlocked)

        env.addIntakeEvent(200)

        let achievement = env.game.achievementSnapshots().first { $0.key == "first.drop" }!
        XCTAssertTrue(achievement.isUnlocked)
        XCTAssertTrue(env.game.hasUnseenAchievements)
    }

    func testAchievementRelocksWhenConditionNoLongerHolds() {
        let env = GameEnv()
        let ref = env.addIntakeEvent(1000) // «Великий ковток» — 1 л за раз

        XCTAssertTrue(env.game.achievementSnapshots().first { $0.key == "big.gulp" }!.isUnlocked)
        let xpAfterUnlock = env.game.levelProgress().totalXp

        env.metrics.revert(sourceRef: ref, at: env.clock.now)

        XCTAssertFalse(
            env.game.achievementSnapshots().first { $0.key == "big.gulp" }!.isUnlocked,
            "RevertPolicy.full знімає досягнення разом з дією"
        )
        XCTAssertLessThan(env.game.levelProgress().totalXp, xpAfterUnlock)
    }

    func testAchievementSurvivesUndoWhenStillEarnedByOtherData() {
        let env = GameEnv()
        env.addIntakeEvent(1000, hour: 9)
        let second = env.addIntakeEvent(1000, hour: 11)

        env.metrics.revert(sourceRef: second, at: env.clock.now)

        XCTAssertTrue(
            env.game.achievementSnapshots().first { $0.key == "big.gulp" }!.isUnlocked,
            "умова досі виконана іншим записом — досягнення лишається"
        )
    }

    func testStreakAchievementsUseLongestStreak() {
        let env = GameEnv()
        for day in 16...18 { env.completeDay("2026-07-\(day)") }

        let unlocked = env.game.achievementSnapshots().filter(\.isUnlocked).map(\.key)
        XCTAssertTrue(unlocked.contains("streak.3"))
        XCTAssertFalse(unlocked.contains("streak.7"))
    }

    func testDailyQuestProgressAndCompletion() {
        let env = GameEnv(goalMl: 1000)
        env.addIntakeEvent(400, hour: 9)

        var quest = env.game.dailyQuests().first { $0.key == "daily.goal" }!
        XCTAssertFalse(quest.isDone)
        XCTAssertEqual(quest.progress, 400)
        XCTAssertEqual(quest.target, 1000)

        env.addIntakeEvent(700, hour: 11)

        quest = env.game.dailyQuests().first { $0.key == "daily.goal" }!
        XCTAssertTrue(quest.isDone)
        XCTAssertEqual(quest.progressLabel, "Готово")
    }

    func testQuestReopensAfterUndo() {
        let env = GameEnv(goalMl: 1000)
        env.addIntakeEvent(400, hour: 9)
        let closing = env.addIntakeEvent(700, hour: 11)
        XCTAssertTrue(env.game.dailyQuests().first { $0.key == "daily.goal" }!.isDone)
        let xpWithQuest = env.game.levelProgress().totalXp

        env.metrics.revert(sourceRef: closing, at: env.clock.now)

        XCTAssertFalse(
            env.game.dailyQuests().first { $0.key == "daily.goal" }!.isDone,
            "завдання повертається в активні"
        )
        XCTAssertLessThan(env.game.levelProgress().totalXp, xpWithQuest)
    }

    func testEntriesQuestCountsRecords() {
        let env = GameEnv()
        for hour in 8...10 { env.addIntakeEvent(200, hour: hour) }

        let quest = env.game.dailyQuests().first { $0.key == "daily.entries4" }!
        XCTAssertEqual(quest.progressLabel, "3/4")
        XCTAssertFalse(quest.isDone)

        env.addIntakeEvent(200, hour: 11)
        XCTAssertTrue(env.game.dailyQuests().first { $0.key == "daily.entries4" }!.isDone)
    }

    func testCompletedQuestsSplitOutOfActive() {
        let env = GameEnv()
        XCTAssertEqual(env.game.dailyQuests().active.count, QuestCatalog.dailySlots, "спершу активні всі")
        XCTAssertTrue(env.game.dailyQuests().completed.isEmpty)

        // Норма 2000 мл двома порціями: денна ціль закрита, «4 записи» — ще ні.
        _ = env.addIntakeEvent(1000, hour: 8)
        _ = env.addIntakeEvent(1000, hour: 9)

        let mixed = env.game.dailyQuests()
        XCTAssertEqual(mixed.completed.map(\.key), ["daily.goal"])
        XCTAssertEqual(mixed.active.map(\.key), ["daily.entries4"])

        _ = env.addIntakeEvent(100, hour: 10)
        _ = env.addIntakeEvent(100, hour: 11)

        let done = env.game.dailyQuests()
        XCTAssertTrue(done.active.isEmpty, "виконане завдання зникає з активних")
        XCTAssertEqual(done.completed.count, QuestCatalog.dailySlots)
    }

    func testOnlyTwoDailyQuestsAreIssued() {
        let env = GameEnv()
        XCTAssertEqual(env.game.dailyQuests().count, QuestCatalog.dailySlots)
    }

    func testWeeklyQuestCountsGoalDays() {
        let env = GameEnv()
        for day in 13...17 { env.completeDay("2026-07-\(day)") } // Пн–Пт того самого тижня

        let quest = env.game.weeklyQuests().first { $0.key == "weekly.goal5days" }!
        XCTAssertTrue(quest.isDone, "5 днів з нормою за тиждень")
    }

    func testLevelUpFromRepeatedIntakes() {
        let env = GameEnv()
        for index in 0..<25 { env.addIntakeEvent(100, hour: 8 + index % 12) }

        XCTAssertGreaterThan(env.game.levelProgress().level, 1)
    }

    func testPrizeActivationGrantsFreezeToken() {
        let env = GameEnv()
        let item = RewardItem(defKey: "streak.freeze", source: .quest, acquiredAt: env.clock.now)
        env.store.insertReward(item)
        env.store.save()

        XCTAssertTrue(env.game.activatePrize(id: item.id))
        XCTAssertEqual(env.game.streakSummary().freezeTokens, 1)
        XCTAssertFalse(env.game.activatePrize(id: item.id), "приз не можна активувати двічі")
    }

    func testLevelRewardsMarkUnlockedUpToCurrentLevel() {
        let env = GameEnv()
        let rewards = env.game.levelRewards()
        XCTAssertTrue(rewards.first { $0.level == 1 }!.isUnlocked)
        XCTAssertFalse(rewards.first { $0.level == 5 }!.isUnlocked)
        XCTAssertTrue(rewards.contains { $0.level == 5 && $0.key == "streak.freeze" },
                      "кожен 5-й рівень додає заморозку серії")
    }
}

@MainActor
final class LevelRewardGrantTests: XCTestCase {
    func testLevelUpPutsPrizesIntoInventory() {
        let env = GameEnv()
        XCTAssertTrue(env.game.prizes().isEmpty, "на 1-му рівні призів ще немає")

        for index in 0..<40 { env.addIntakeEvent(150, hour: 8 + index % 12) }

        let level = env.game.levelProgress().level
        XCTAssertGreaterThan(level, 1)
        XCTAssertFalse(env.game.prizes().isEmpty, "нові рівні видають призи в інвентар")
    }

    func testGrantIsIdempotent() {
        let env = GameEnv()
        for index in 0..<40 { env.addIntakeEvent(150, hour: 8 + index % 12) }
        let before = env.game.prizes().count

        env.game.grantLevelRewards(at: env.clock.now)
        env.game.grantLevelRewards(at: env.clock.now)

        XCTAssertEqual(env.game.prizes().count, before, "повторна видача не дублює призи")
    }
}
