import XCTest
import Core
import Metrics
import Persistence
@testable import Gamification

/// Перебалансування першого тижня (WAT-60, SPEC-ACHIEVEMENTS-CATALOG §10): знятим — архів, а не видалення,
/// відкрите не забирається, нові умови історії.
@MainActor
final class CatalogRebalanceTests: XCTestCase {

    // MARK: - Архів (§10.2)

    /// На чистій установці зняте не відкривається й не видно — навіть коли умова виконана.
    func testRetiredNeverUnlocksAndStaysHidden() {
        let env = GameEnv()
        env.drink(1000, on: "2026-07-18", hour: 9)

        XCTAssertEqual(env.progressValue("volume.1l"), 0, "зняте не рахується в проході")
        XCTAssertNil(env.achievement("volume.1l"), "«Глечика» немає в знімку, як пасхалки до знахідки")
        XCTAssertFalse(env.game.achievementSnapshots().contains(where: \.isRetired))
    }

    /// Відкрите до архівації — звичайна плитка, але поза «Відкрито N / M»; «Колекція» його рахує.
    func testRetiredUnlockedBeforeStaysVisibleOutsideTheTally() {
        let env = GameEnv()
        let before = env.game.achievementSnapshots().tally
        env.unlockBefore("volume.1l", at: GameEnv.date("2026-07-01"))

        let snapshot = env.achievement("volume.1l")
        XCTAssertEqual(snapshot?.isUnlocked, true)
        XCTAssertEqual(snapshot?.isRetired, true)
        XCTAssertEqual(snapshot?.title, "Глечик")
        let after = env.game.achievementSnapshots().tally
        XCTAssertEqual(after.total, before.total, "зняте лічильник не роздуває")
        XCTAssertEqual(after.unlocked, before.unlocked)

        for key in ["volume.10l", "first.drop", "day.goal", "big.gulp", "streak.3", "streak.7", "streak.14", "goal.days5", "marathon"] {
            env.unlockBefore(key, at: GameEnv.date("2026-07-01"))
        }
        env.drink(200, on: "2026-07-18", hour: 9)
        XCTAssertTrue(env.isUnlocked("collection.10"), "9 відкритих + зняте = 10 — його заробили")
    }

    /// «Усе зібрано» знятих не містить; категорії фільтра — лише з чинних.
    func testCompleteCatalogExcludesRetired() {
        XCTAssertFalse(AchievementCatalog.all.contains { $0.isRetired && $0.isCore })
        XCTAssertEqual(
            AchievementCatalog.definition("collection.all")?.target,
            Double(AchievementCatalog.active.filter(\.isCore).count - 1)
        )
        XCTAssertFalse(AchievementCatalog.evaluationOrder.contains(where: \.isRetired))
    }

    // MARK: - Відкат з часу події (§10.3)

    /// Відкрите за старим порогом не забирається відкатом пізнішої порції, хоч нова умова й не виконана.
    func testUndoKeepsAchievementUnlockedBeforeTheEvent() {
        let env = GameEnv()
        env.unlockBefore("rhythm.morning", at: GameEnv.date("2026-07-10"))
        let id = env.drink(300, on: "2026-07-18", hour: 9)

        env.undo(id, at: env.clock.now)

        XCTAssertTrue(env.isUnlocked("rhythm.morning"), "«Добрий ранок» відкрито 10 липня — від порції 18-го не залежало")
    }

    /// Відкрите самою порцією чи пізніше — знімається, як і раніше.
    func testUndoStillRelocksWhatTheEventUnlocked() {
        let env = GameEnv()
        let id = env.drink(1000, on: "2026-07-18", hour: 9)
        XCTAssertTrue(env.isUnlocked("big.gulp"))

        env.undo(id, at: env.clock.now)

        XCTAssertFalse(env.isUnlocked("big.gulp"))
    }
}

extension GameEnv {
    /// Досягнення, відкрите раніше — до WAT-60 чи за старим порогом: прогрес, як його лишила стара версія.
    func unlockBefore(_ key: String, at date: Date) {
        let progress = store.achievementProgress(defKey: key) ?? {
            let created = AchievementProgress(defKey: key, target: 1)
            store.insertAchievement(created)
            return created
        }()
        progress.value = progress.target
        progress.unlockedAt = date
        store.save()
    }
}

// MARK: - Нові умови історії (§10.1)

@MainActor
final class RebalancedHistoryTests: XCTestCase {
    /// Рівно норма двічі поспіль — це «В яблучко», а не близнюки.
    func testExactGoalTwiceIsNotTwins() {
        let env = GameEnv()
        env.clock.set(GameEnv.date("2026-07-22", hour: 9))
        env.drink(2000, on: "2026-07-20")
        env.drink(2000, on: "2026-07-21")
        env.drink(200, on: "2026-07-22", hour: 9)
        XCTAssertEqual(env.progressValue("special.twins"), 0)

        let other = GameEnv()
        other.clock.set(GameEnv.date("2026-07-22", hour: 9))
        other.drink(1850, on: "2026-07-20")
        other.drink(1850, on: "2026-07-21")
        other.drink(200, on: "2026-07-22", hour: 9)
        XCTAssertTrue(other.isUnlocked("special.twins"))
    }
}
