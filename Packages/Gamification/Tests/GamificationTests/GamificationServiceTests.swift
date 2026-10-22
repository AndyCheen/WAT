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

        // 300 мл × 5 XP / 250 мл = 6 XP + 25 XP за досягнення «Перша крапля»
        XCTAssertEqual(env.game.levelProgress().totalXp, 6 + 25)
    }

    func testUndoOfIntakeReturnsXP() {
        let env = GameEnv()
        let ref = env.addIntakeEvent(300)
        XCTAssertEqual(env.game.levelProgress().totalXp, 31)

        env.metrics.revert(sourceRef: ref, at: env.clock.now)

        XCTAssertEqual(env.game.levelProgress().totalXp, 0, "відкат дії повертає досвід (ТЗ §5.2)")
    }

    func testDailyGoalAwardsBonusXP() {
        let env = GameEnv()
        env.completeDay("2026-07-18")

        // 50 XP за норму дня; завдань тут немає (`GameEnv` — без пікерів).
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
        let env = GameEnv(quests: QuestForcing(daily: ["starter.firstGoal"]))
        env.addIntakeEvent(400, hour: 9)

        var quest = env.game.dailyQuests().first { $0.key == "starter.firstGoal" }!
        XCTAssertFalse(quest.isDone)
        XCTAssertEqual(quest.progress, 400)
        XCTAssertEqual(quest.target, 2000)
        XCTAssertEqual(quest.kind, .volume)

        env.addIntakeEvent(1700, hour: 11)

        quest = env.game.dailyQuests().first { $0.key == "starter.firstGoal" }!
        XCTAssertTrue(quest.isDone)
    }

    func testQuestReopensAfterUndo() {
        let env = GameEnv(quests: QuestForcing(daily: ["starter.firstGoal"]))
        env.addIntakeEvent(400, hour: 9)
        let closing = env.addIntakeEvent(1700, hour: 11)
        XCTAssertTrue(env.game.dailyQuests().first { $0.key == "starter.firstGoal" }!.isDone)
        let xpWithQuest = env.game.levelProgress().totalXp

        let log = env.dayLogs.existingDayLog(for: DayKey(rawValue: "2026-07-18"))!
        log.totalMl = 400
        log.countedMl = 400
        env.metrics.revert(sourceRef: closing, at: env.clock.now)

        XCTAssertFalse(
            env.game.dailyQuests().first { $0.key == "starter.firstGoal" }!.isDone,
            "завдання повертається в активні"
        )
        XCTAssertLessThan(env.game.levelProgress().totalXp, xpWithQuest)
        XCTAssertTrue(env.metrics.events(.questCompleted).isEmpty, "подію завдання теж відкочено (SPEC-QUESTS §7)")
    }

    /// Д6: лише порції від 150 мл (принцип 4), N = G / P у межах 3…5.
    func testGlassesQuestCountsOnlyRealGlasses() {
        let env = GameEnv(quests: QuestForcing(daily: ["daily.glasses"]))
        for hour in 8...11 { env.addIntake(200, hour: hour) }
        env.addIntake(100, hour: 12)

        var quest = env.game.dailyQuests().first { $0.key == "daily.glasses" }!
        XCTAssertEqual(quest.count, 5, "2000 / 250 = 8 → не більше 5")
        XCTAssertEqual(quest.progress, 4, "порція 100 мл не рахується")
        XCTAssertFalse(quest.isDone)

        env.addIntake(150, hour: 13)
        quest = env.game.dailyQuests().first { $0.key == "daily.glasses" }!
        XCTAssertTrue(quest.isDone)
    }

    func testCompletedQuestsSplitOutOfActive() {
        let env = GameEnv(quests: QuestForcing(daily: ["starter.firstGoal", "daily.glasses"]))
        XCTAssertEqual(env.game.dailyQuests().active.count, 2, "спершу активні всі")
        XCTAssertTrue(env.game.dailyQuests().completed.isEmpty)

        // Норма 2000 мл двома порціями: денна ціль закрита, «5 склянок» — ще ні.
        env.addIntake(1000, hour: 8)
        env.addIntake(1000, hour: 9)

        let mixed = env.game.dailyQuests()
        XCTAssertEqual(mixed.completed.map(\.key), ["starter.firstGoal"])
        XCTAssertEqual(mixed.active.map(\.key), ["daily.glasses"])

        for hour in 10...12 { env.addIntake(200, hour: hour) }

        let done = env.game.dailyQuests()
        XCTAssertTrue(done.active.isEmpty, "виконане завдання зникає з активних")
        XCTAssertEqual(done.completed.count, 2)
    }

    /// День 1 людини — дві стартові (SPEC-QUESTS §3.3), тижневих у суботу немає (§5.1).
    func testFirstDayGetsStarterPair() {
        let env = GameEnv(quests: nil)
        let board = env.game.questBoard()
        XCTAssertEqual(board.daily.map(\.key), ["starter.firstGlass", "starter.halfGoal"])
        XCTAssertEqual(board.daily.map(\.rewardXp), [15, 15])
        XCTAssertTrue(board.weekly.isEmpty)
        XCTAssertTrue(board.weeklyStartsMonday)
    }

    func testWeeklyQuestCountsGoalDays() {
        let env = GameEnv(day: 13, hour: 8, quests: QuestForcing(weekly: [("weekly.goalDays", 5)]))
        for day in 13...17 { env.completeDay("2026-07-\(day)") } // Пн–Пт того самого тижня

        let quest = env.game.weeklyQuests(at: GameEnv.date(day: 17, hour: 20)).first { $0.key == "weekly.goalDays" }!
        XCTAssertTrue(quest.isDone, "5 днів з нормою за тиждень")
        XCTAssertEqual(quest.rewardXp, 100, "N = 5 — середнє")
    }

    /// Вада до WAT-63: відкат порції, що закрила тижневе, лишав `quest.weeklyCompleted` — і «Тижнева мета» трималась.
    func testUndoingWeeklyClosingPortionRevertsItsEvents() {
        let env = GameEnv(day: 13, hour: 8, quests: QuestForcing(weekly: [("weekly.goalDays", 2)]))
        env.clock.set(GameEnv.date("2026-07-14", hour: 20))
        env.goalDay("2026-07-13")
        let closing = env.drink(2000, on: "2026-07-14")
        XCTAssertTrue(env.isUnlocked("quest.first"))
        XCTAssertEqual(env.metrics.events(.weeklyQuestCompleted).count, 1)
        let xpWithQuest = env.game.levelProgress().totalXp

        env.undo(closing, at: env.clock.now)

        XCTAssertFalse(env.game.weeklyQuests().first!.isDone)
        XCTAssertTrue(env.metrics.events(.weeklyQuestCompleted).isEmpty)
        XCTAssertTrue(env.metrics.events(.questCompleted).isEmpty)
        XCTAssertFalse(env.isUnlocked("quest.first"), "«Тижнева мета» знімається разом із завданням")
        XCTAssertLessThan(env.game.levelProgress().totalXp, xpWithQuest)
    }

    func testLevelUpFromRepeatedIntakes() {
        let env = GameEnv(quests: nil)
        for index in 0..<25 { env.addIntakeEvent(100, hour: 8 + index % 12) }

        XCTAssertGreaterThan(env.game.levelProgress().level, 1)
    }

    func testNextRewardSkipsLevelsWithoutPrize() {
        let env = GameEnv()
        let road = env.game.levelRoad()
        XCTAssertEqual(road.progress.level, 1)
        XCTAssertEqual(road.nextReward?.level, 2, "перший приз — на 2-му рівні")
        XCTAssertEqual(road.nodes.first?.status, .passed, "стартовий рівень нагороди не дає")
    }
}

@MainActor
final class LevelRewardGrantTests: XCTestCase {
    func testLevelUpPutsPrizesIntoInventory() {
        let env = GameEnv(quests: nil)
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
