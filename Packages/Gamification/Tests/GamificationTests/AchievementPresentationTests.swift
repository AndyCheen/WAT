import XCTest
import Core
import Metrics
import Persistence
@testable import Gamification

/// Правила подачі досягнень з SPEC-ACHIEVEMENTS: категорії, знімок, сортування, вітрина,
/// черга розблокувань для тоста. Усе це доменне, тому перевіряється тут, а не в e2e.
@MainActor
final class AchievementPresentationTests: XCTestCase {

    // MARK: - Категорії (§3.1)

    func testCategoriesHaveNoPseudoAllAndGeneralHasOwnTitle() {
        XCTAssertEqual(AchievementCatalog.categories, [.general, .streak, .volume])
        XCTAssertEqual(AchievementCategory.general.title, "Загальні", "«Всі» — псевдо-таб, не категорія")
        XCTAssertFalse(AchievementCatalog.categories.contains(.secret), "порожня категорія в меню не потрапляє")
    }

    // MARK: - Знімок (§2)

    func testSnapshotCarriesRewardUnlockDateAndNewFlag() {
        let env = GameEnv()
        env.addIntakeEvent(300)

        let drop = env.game.achievementSnapshots().first { $0.key == "first.drop" }!
        XCTAssertEqual(drop.rewardXp, 25)
        XCTAssertNotNil(drop.unlockedAt)
        XCTAssertTrue(drop.isNew)
        XCTAssertEqual(drop.state, .unlocked)

        env.game.markAchievementsSeen()
        XCTAssertFalse(env.game.achievementSnapshots().first { $0.key == "first.drop" }!.isNew)
    }

    func testMarkingOneAchievementSeenKeepsOthersNew() {
        let env = GameEnv()
        env.addIntakeEvent(1000) // «Перша крапля» + «Великий ковток»

        env.game.markAchievementSeen(key: "big.gulp")

        let items = env.game.achievementSnapshots()
        XCTAssertFalse(items.first { $0.key == "big.gulp" }!.isNew)
        XCTAssertTrue(items.first { $0.key == "first.drop" }!.isNew, "крапка гасне лише на переглянутій картці")
    }

    func testStateDistinguishesUntouchedFromInProgress() {
        let env = GameEnv()
        env.addIntakeEvent(600)

        let items = env.game.achievementSnapshots()
        XCTAssertEqual(items.first { $0.key == "big.gulp" }!.state, .inProgress, "600 з 1000 мл")
        XCTAssertEqual(items.first { $0.key == "streak.30" }!.state, .locked, "нульовий прогрес")
        XCTAssertEqual(items.first { $0.key == "big.gulp" }!.valueLabel, "600 / 1000")
    }

    // MARK: - Фільтр стану (§3.2)

    func testStateFilters() {
        let items = [
            Self.item("a", value: 1, target: 1, unlocked: true),
            Self.item("b", value: 3, target: 7),
            Self.item("c", value: 0, target: 7)
        ]
        func keys(_ filter: AchievementStateFilter) -> [String] { items.filter(filter.matches).map(\.key) }

        XCTAssertEqual(keys(.all), ["a", "b", "c"])
        XCTAssertEqual(keys(.inProgress), ["b"])
        XCTAssertEqual(keys(.unlocked), ["a"])
        XCTAssertEqual(keys(.locked), ["b", "c"], "«Закриті» — усе невідкрите, включно з тим, що в процесі")
    }

    // MARK: - Сортування (§3.4)

    func testSortOrderNewThenClosestThenUnlockedThenUntouched() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let items = [
            Self.item("untouched.1", value: 0, target: 5),
            Self.item("old.unlocked", value: 1, target: 1, unlocked: true, at: early),
            Self.item("far", value: 1, target: 10),
            Self.item("untouched.2", value: 0, target: 5),
            Self.item("new.early", value: 1, target: 1, unlocked: true, at: early, isNew: true),
            Self.item("close", value: 9, target: 10),
            Self.item("recent.unlocked", value: 1, target: 1, unlocked: true, at: late),
            Self.item("new.late", value: 1, target: 1, unlocked: true, at: late, isNew: true)
        ]

        XCTAssertEqual(items.sortedForDisplay.map(\.key), [
            "new.late", "new.early",
            "close", "far",
            "recent.unlocked", "old.unlocked",
            "untouched.1", "untouched.2"
        ])
    }

    // MARK: - Вітрина 3f (§4.1)

    func testShowcaseSkipsUntouchedAndCapsAtTwoRows() {
        let items = (0..<12).map { Self.item("p\($0)", value: 1, target: 5) }
            + [Self.item("zero", value: 0, target: 5)]

        XCTAssertEqual(items.showcase.count, 8)
        XCTAssertFalse(items.showcase.contains { $0.key == "zero" })
        XCTAssertTrue([Self.item("zero", value: 0, target: 5)].showcase.isEmpty, "чиста установка — порожня вітрина")
    }

    // MARK: - Черга розблокувань для тоста (§8)

    func testRecentUnlocksAreTakenOnce() {
        let env = GameEnv()
        XCTAssertTrue(env.game.takeRecentUnlocks().isEmpty, "стартовий refresh у чергу не потрапляє")

        env.addIntakeEvent(1000)
        XCTAssertEqual(Set(env.game.takeRecentUnlocks().map(\.key)), ["first.drop", "big.gulp"])
        XCTAssertTrue(env.game.takeRecentUnlocks().isEmpty, "черга очищається після читання")
    }

    func testRevertedUnlockLeavesTheQueue() {
        let env = GameEnv()
        env.addIntakeEvent(200)
        _ = env.game.takeRecentUnlocks()

        let ref = env.addIntakeEvent(1000)
        env.metrics.revert(sourceRef: ref, at: env.clock.now)

        XCTAssertTrue(env.game.takeRecentUnlocks().isEmpty, "відкочене досягнення тосту не заслуговує")
    }

    // MARK: - Допоміжне

    private static func item(
        _ key: String, value: Double, target: Double,
        unlocked: Bool = false, at date: Date? = nil, isNew: Bool = false
    ) -> AchievementSnapshot {
        AchievementSnapshot(
            key: key, title: key, details: "", emoji: "💧", category: .general,
            value: value, target: target, isUnlocked: unlocked, isSecret: false,
            rewardXp: 10, unlockedAt: unlocked ? (date ?? Date(timeIntervalSince1970: 0)) : nil,
            isNew: isNew
        )
    }
}
