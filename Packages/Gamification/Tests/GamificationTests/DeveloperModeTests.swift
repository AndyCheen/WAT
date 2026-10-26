import XCTest
import Core
import Persistence
import Metrics
@testable import Gamification

/// Режим розробника (WAT-68): дії повз правила йдуть далі звичайним шляхом гри — XP, рівень, черга вікна відкриття, —
/// а відкат порції їх не знімає.
@MainActor
final class DeveloperModeTests: XCTestCase {

    // MARK: - Досягнення

    func testUnlockGivesXpAndQueuesTheCelebration() {
        let env = GameEnv()
        let reward = AchievementCatalog.definition("big.gulp")!.rewardXp

        XCTAssertTrue(env.game.developerUnlock(achievement: "big.gulp"))

        XCTAssertTrue(env.isUnlocked("big.gulp"))
        XCTAssertEqual(env.game.levelProgress().totalXp, reward)
        XCTAssertEqual(env.game.pendingCelebrations(since: .distantPast).map(\.key), ["big.gulp"])
        XCTAssertFalse(env.game.developerUnlock(achievement: "big.gulp"), "відкрите вдруге не відкривається")
    }

    func testUnlockedByDeveloperSurvivesUndo() {
        let env = GameEnv()
        let intake = env.drink(250, on: "2026-07-18", hour: 13)
        env.game.developerUnlock(achievement: "big.gulp")

        env.undo(intake, at: env.clock.now)

        XCTAssertTrue(env.isUnlocked("big.gulp"), "умова тут ні до чого — знімає лише «Закрити»")
    }

    func testRelockTakesXpBackAndUnlocksAgainWithNextEvent() {
        let env = GameEnv()
        env.drink(250, on: "2026-07-18", hour: 10)
        XCTAssertTrue(env.isUnlocked("first.drop"))
        let before = env.game.levelProgress().totalXp

        XCTAssertTrue(env.game.developerRelock(achievement: "first.drop"))

        XCTAssertFalse(env.isUnlocked("first.drop"))
        XCTAssertEqual(env.game.levelProgress().totalXp, before - AchievementCatalog.definition("first.drop")!.rewardXp)
        env.drink(250, on: "2026-07-18", hour: 11)
        XCTAssertTrue(env.isUnlocked("first.drop"), "умова виконана — наступна порція відкриває знову")
    }

    func testEggsAndRetiredAreListedUnmasked() {
        let env = GameEnv()
        let all = env.game.developerAchievements()
        XCTAssertEqual(all.count, AchievementCatalog.all.count)
        XCTAssertTrue(all.contains { $0.isEgg })
        XCTAssertTrue(all.contains { $0.isRetired })
        XCTAssertFalse(all.contains { $0.title == AchievementSnapshot.maskedTitle })
    }

    // MARK: - Завдання

    func testIssuedDailyQuestShowsOnBoardAndCompletesWithXp() throws {
        let env = GameEnv()
        XCTAssertTrue(env.game.developerIssueQuest(key: "daily.glasses"))
        let quest = try XCTUnwrap(env.game.dailyQuests().first { $0.key == "daily.glasses" })
        XCTAssertFalse(quest.isDone)

        XCTAssertTrue(env.game.developerComplete(quest: quest.id))

        XCTAssertTrue(env.game.dailyQuests().first { $0.id == quest.id }?.isDone ?? false)
        XCTAssertEqual(env.game.levelProgress().totalXp, quest.rewardXp)
    }

    func testCompletedByDeveloperSurvivesUndo() throws {
        let env = GameEnv()
        let intake = env.drink(250, on: "2026-07-18", hour: 13)
        env.game.developerIssueQuest(key: "daily.glasses")
        let quest = try XCTUnwrap(env.game.dailyQuests().first { $0.key == "daily.glasses" })
        env.game.developerComplete(quest: quest.id)

        env.undo(intake, at: env.clock.now)

        XCTAssertTrue(env.game.dailyQuests().first { $0.id == quest.id }?.isDone ?? false)
    }

    func testCancelHidesQuestAndTakesItsXpBack() throws {
        let env = GameEnv()
        env.game.developerIssueQuest(key: "weekly.goalDays")
        let quest = try XCTUnwrap(env.game.weeklyQuests().first { $0.key == "weekly.goalDays" })
        env.game.developerComplete(quest: quest.id)
        XCTAssertGreaterThan(env.game.levelProgress().totalXp, 0)

        XCTAssertTrue(env.game.developerCancel(quest: quest.id))

        XCTAssertFalse(env.game.weeklyQuests().contains { $0.id == quest.id })
        XCTAssertEqual(env.game.levelProgress().totalXp, 0)
        XCTAssertEqual(env.game.developerQuests().first { $0.id == quest.id }?.state, .cancelled,
                       "у списку розробника скасоване лишається")
    }

    func testSurpriseWithDelayAppearsLater() throws {
        let env = GameEnv(hour: 13)
        XCTAssertTrue(env.game.developerIssueQuest(key: "surprise.glassNow", delayMinutes: 2))

        let surprise = try XCTUnwrap(env.game.questBoard().surprise)
        XCTAssertEqual(surprise.visibleFrom, env.clock.now.addingTimeInterval(120))
        XCTAssertFalse(surprise.isVisible(at: env.clock.now))
        XCTAssertTrue(surprise.isVisible(at: env.clock.now.addingTimeInterval(120)))
    }

    // MARK: - XP, призи, серія

    func testSetLevelLandsOnItsThresholdBothWays() {
        let env = GameEnv()
        env.game.developerSetLevel(6)
        XCTAssertEqual(env.game.levelProgress().level, 6)
        XCTAssertEqual(env.game.levelProgress().xpIntoLevel, 0)
        let prizes = env.game.prizes().count
        XCTAssertGreaterThan(prizes, 0, "рівні 2…6 видали свої призи")

        env.game.developerSetLevel(3)
        XCTAssertEqual(env.game.levelProgress().level, 3)
        XCTAssertEqual(env.game.levelProgress().xpIntoLevel, 0)
        XCTAssertEqual(env.game.prizes().count, prizes, "униз видане лишається")

        env.game.developerSetLevel(6)
        XCTAssertEqual(env.game.prizes().count, prizes, "знову вгору — призи вдруге не видаються")
    }

    func testAlmostNextLevelLeavesTenXp() {
        let env = GameEnv()
        env.game.developerSetLevel(4)
        env.game.developerAlmostNextLevel()
        XCTAssertEqual(env.game.levelProgress().level, 4)
        XCTAssertEqual(env.game.levelProgress().xpLeft, 10)

        env.game.developerAwardXp(10)
        XCTAssertEqual(env.game.levelProgress().level, 5, "рівень піднімає звичайний XP")
    }

    func testLevelOneIsTheFloor() {
        let env = GameEnv()
        env.game.developerSetLevel(3)
        env.game.developerSetLevel(0)
        XCTAssertEqual(env.game.levelProgress().level, 1)
        XCTAssertEqual(env.game.levelProgress().totalXp, 0)
    }

    func testStopBoostExpiresItNow() throws {
        let env = GameEnv()
        let boost = try XCTUnwrap(env.game.grantPrize(key: RewardCatalog.boostKey, source: .seed))
        XCTAssertTrue(env.game.activateBoost(prizeId: boost.id))
        XCTAssertEqual(env.game.xp.boostMultiplier(at: env.clock.now), 2)

        XCTAssertTrue(env.game.developerStopBoost())

        XCTAssertEqual(env.game.xp.boostMultiplier(at: env.clock.now), 1)
        XCTAssertEqual(env.game.prizes().first { $0.id == boost.id }?.state, .expired)
    }

    func testFrozenDayHoldsTheStreakChain() {
        let env = GameEnv(day: 18)
        env.goalDay("2026-07-15")
        env.goalDay("2026-07-16")
        env.goalDay("2026-07-18")
        XCTAssertEqual(env.game.streakSummary().current, 1)

        env.game.developerSetFrozen(true, day: DayKey(rawValue: "2026-07-17"))
        XCTAssertTrue(env.game.isFrozen(DayKey(rawValue: "2026-07-17")))
        XCTAssertEqual(env.game.streakSummary().current, 3, "заморожений день тримає ланцюг, але не додає")

        env.game.developerSetFrozen(false, day: DayKey(rawValue: "2026-07-17"))
        XCTAssertEqual(env.game.streakSummary().current, 1)
    }
}
