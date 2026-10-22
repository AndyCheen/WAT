import XCTest
import Core
import Persistence
@testable import Gamification

/// Черга вікна відкриття (WAT-60, SPEC-ACHIEVEMENTS §8.5): невідсвятковане лежить у базі, доки вікно не закрили.
@MainActor
final class CelebrationQueueTests: XCTestCase {

    func testUnlockWaitsUntilMarkedCelebrated() {
        let env = GameEnv()
        let since = env.clock.now
        env.addIntake(200, hour: 14)

        XCTAssertEqual(env.game.pendingCelebrations(since: since).map(\.key), ["first.drop"])
        XCTAssertEqual(env.game.pendingCelebrations(since: since), env.game.pendingCelebrations(since: since),
                       "читання чергу не чистить — на відміну від `takeRecentUnlocks`")

        env.game.markCelebrated(keys: ["first.drop"])
        XCTAssertTrue(env.game.pendingCelebrations(since: since).isEmpty)
        XCTAssertFalse(env.game.hasUnseenAchievements, "відсвятковане — ще й побачене: крапки «нове» немає")
    }

    /// Відкрите до `celebrationsSince` — відсвятковане: оновлення не показує вікно на десятки сторінок.
    func testUnlockBeforeSinceIsNotQueued() {
        let env = GameEnv()
        env.addIntake(200, hour: 9)
        XCTAssertTrue(env.game.pendingCelebrations(since: GameEnv.date(day: 18, hour: 10)).isEmpty)
        XCTAssertEqual(env.game.pendingCelebrations(since: GameEnv.date(day: 18, hour: 9)).map(\.key), ["first.drop"],
                       "межа включна: відкрите тією ж миттю — уже після")
    }

    /// Кілька за одну дію — за часом відкриття, а однаковий час — у порядку каталогу.
    func testQueueKeepsUnlockOrder() {
        let env = GameEnv()
        let since = env.clock.now
        env.addIntake(1000, hour: 14)
        XCTAssertEqual(env.game.pendingCelebrations(since: since).map(\.key), ["first.drop", "big.gulp"])
    }

    /// Відкат `celebratedAt` не скидає: зняте видаленою порцією й відкрите знову вдруге вікна не отримує.
    func testRevertKeepsCelebratedAndReunlockIsNotQueued() {
        let env = GameEnv()
        let since = env.clock.now
        let id = env.addIntake(200, hour: 14)
        env.game.markCelebrated(keys: ["first.drop"])

        env.removeIntake(id)
        XCTAssertFalse(env.isUnlocked("first.drop"), "єдина порція — досягнення знято")
        XCTAssertNotNil(env.store.achievementProgress(defKey: "first.drop")?.celebratedAt)

        env.restoreIntake(id)
        XCTAssertTrue(env.isUnlocked("first.drop"))
        XCTAssertTrue(env.game.pendingCelebrations(since: since).isEmpty, "удруге не святкується")
    }

    /// Невідсвятковане й зняте відкатом зникає з черги — святкувати нічого.
    func testRevertedBeforeCelebrationLeavesTheQueue() {
        let env = GameEnv()
        let since = env.clock.now
        let id = env.addIntake(200, hour: 14)
        env.removeIntake(id)
        XCTAssertTrue(env.game.pendingCelebrations(since: since).isEmpty)
    }

    /// Зняте з каталогу в черзі не буває — навіть відкрите до архівації й невідсвятковане.
    func testRetiredIsNeverQueued() {
        let env = GameEnv()
        let since = GameEnv.date(day: 1, hour: 0)
        env.unlockBefore("volume.1l", at: GameEnv.date(day: 2, hour: 9))
        env.unlockBefore("first.drop", at: GameEnv.date(day: 2, hour: 9))
        XCTAssertEqual(env.game.pendingCelebrations(since: since).map(\.key), ["first.drop"])
    }

    // MARK: - «Далі» (§8.4)

    func testHigherStepsFollowTheSameRule() {
        XCTAssertEqual(AchievementCatalog.higherSteps(after: "streak.3").first?.key, "streak.7")
        XCTAssertTrue(AchievementCatalog.higherSteps(after: "streak.3").allSatisfy { !$0.isSecret && !$0.isRetired })
        let targets = AchievementCatalog.higherSteps(after: "streak.3").map(\.target)
        XCTAssertEqual(targets, targets.sorted(), "від найменшої цілі")
        XCTAssertTrue(AchievementCatalog.higherSteps(after: "collection.all").isEmpty, "вершина — без сходинки")
    }
}
