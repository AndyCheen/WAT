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

    func testCategoriesAreTheEightFiltersWithoutPseudoAll() {
        XCTAssertEqual(AchievementCatalog.categories, [
            .water, .streak, .regularity, .dayRhythm, .stats, .game, .discovery, .special
        ], "8 фільтрів у фіксованому порядку (SPEC-ACHIEVEMENTS-CATALOG §3)")
        XCTAssertEqual(AchievementCatalog.categories.map(\.title), [
            "Вода", "Серії", "Регулярність", "Ритм дня", "Статистика", "Гра", "Відкриття", "Особливі"
        ])
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

    // MARK: - Підпис прогресу: об'єм у мл / л (WAT-52)

    /// Одиниця — від правила, не позначкою в рядку: об'єм міряють лише «Великий ковток» і драбина `volume.*`.
    func testVolumeUnitComesFromTheRule() {
        let volume = AchievementCatalog.all.filter { $0.unit == .milliliters }.map(\.key)
        XCTAssertEqual(Set(volume), [
            "big.gulp", "volume.1l", "volume.10l", "volume.50l", "volume.100l",
            "volume.250l", "volume.500l", "volume.1000l"
        ])
        XCTAssertEqual(AchievementCatalog.definition("portions.1000")?.unit, .count, "1000 порцій — штуки, хоч ціль та сама, що в «Ковтка»")
        XCTAssertEqual(AchievementRule.count(.intakeAdded).unit, .count, "кількість подій — штуки й на об'ємній метриці")
        XCTAssertEqual(AchievementRule.metric(MetricRule(key: .partMorning)).unit, .milliliters)
    }

    /// Ціль понад 1 л — літри з крапкою, як на кнопках порцій; плитка компактно, картка з пробілами.
    func testVolumeAboveOneLitreIsShownInLitres() {
        func bucket(_ ml: Double) -> AchievementSnapshot { Self.item("volume.10l", value: ml, target: 10_000, unit: .milliliters) }

        XCTAssertEqual(bucket(0).progressLabel, "0/10")
        XCTAssertEqual(bucket(0).valueLabel, "0 / 10")
        XCTAssertEqual(bucket(0).unitLabel, "л")
        XCTAssertEqual(bucket(3450).progressLabel, "3.4/10", "десяті — вниз")
        XCTAssertEqual(bucket(3000).progressLabel, "3/10", "без «3.0»")
        XCTAssertEqual(bucket(9999).progressLabel, "9.9/10", "у закритого не «10/10»")

        func ton(_ ml: Double) -> AchievementSnapshot { Self.item("volume.1000l", value: ml, target: 1_000_000, unit: .milliliters) }
        XCTAssertEqual(ton(0).progressLabel, "0/1000")
        XCTAssertEqual(ton(500).progressLabel, "0.5/1000")
        XCTAssertEqual(ton(123_456).progressLabel, "123/1000", "від 10 л — цілі літри: десяті там шум")
        XCTAssertEqual(ton(999_999).valueLabel, "999 / 1000")
    }

    /// Ціль до 1 л — мілілітри: так на кнопках порцій, і «0.25/1 л» про одну пляшку читається гірше.
    func testVolumeUpToOneLitreStaysInMillilitres() {
        let gulp = Self.item("big.gulp", value: 250, target: 1000, unit: .milliliters)
        XCTAssertEqual(gulp.progressLabel, "250/1000")
        XCTAssertEqual(gulp.valueLabel, "250 / 1000")
        XCTAssertEqual(gulp.unitLabel, "мл")
        XCTAssertEqual(gulp.spokenProgress, "250 із 1000 мілілітрів")
    }

    /// VoiceOver — словами: «слеш» і літеру «л» він не перекладає. Слово узгоджене з ціллю, кома — українська.
    func testSpokenProgressUsesWordsAndAgreesWithTarget() {
        XCTAssertEqual(Self.item("a", value: 3450, target: 10_000, unit: .milliliters).spokenProgress, "3,4 із 10 літрів")
        XCTAssertEqual(Self.item("b", value: 1200, target: 2000, unit: .milliliters).spokenProgress, "1,2 із 2 літри")
        XCTAssertEqual(Self.item("c", value: 1200, target: 2500, unit: .milliliters).spokenProgress, "1,2 із 2,5 літра")
        XCTAssertEqual(Self.item("d", value: 5, target: 7).spokenProgress, "5 із 7", "штуки — як і були")
        XCTAssertNil(Self.item("d", value: 5, target: 7).unitLabel)
        XCTAssertEqual(Self.item("d", value: 5, target: 7).progressLabel, "5/7")
    }

    /// Знімок із рушія несе одиницю з каталогу: «Відро» після 600 мл — «0.6/10 л», «Ковток» — «600/1000 мл».
    func testEngineSnapshotsCarryTheUnit() {
        let env = GameEnv()
        env.addIntakeEvent(600)

        let items = env.game.achievementSnapshots()
        let bucket = items.first { $0.key == "volume.10l" }!
        XCTAssertEqual(bucket.unit, .milliliters)
        XCTAssertEqual("\(bucket.progressLabel) \(bucket.unitLabel!)", "0.6/10 л")
        let gulp = items.first { $0.key == "big.gulp" }!
        XCTAssertEqual("\(gulp.valueLabel) \(gulp.unitLabel!)", "600 / 1000 мл")
        XCTAssertEqual(items.first { $0.key == "streak.30" }!.unit, .count)
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
        XCTAssertEqual(Set(env.game.takeRecentUnlocks().achievements.map(\.key)), ["first.drop", "big.gulp", "volume.1l"])
        XCTAssertTrue(env.game.takeRecentUnlocks().isEmpty, "черга очищається після читання")
    }

    func testRevertedUnlockLeavesTheQueue() {
        let env = GameEnv()
        env.addIntake(200, hour: 9)
        _ = env.game.takeRecentUnlocks()

        let ref = env.addIntake(1000, hour: 10)
        env.removeIntake(ref)

        XCTAssertTrue(env.game.takeRecentUnlocks().isEmpty, "відкочене досягнення тосту не заслуговує")
    }

    // MARK: - Допоміжне

    private static func item(
        _ key: String, value: Double, target: Double, unit: AchievementUnit = .count,
        unlocked: Bool = false, at date: Date? = nil, isNew: Bool = false
    ) -> AchievementSnapshot {
        AchievementSnapshot(
            key: key, title: key, details: "", emoji: "💧", category: .water,
            value: value, target: target, unit: unit, isUnlocked: unlocked, isSecret: false,
            rewardXp: 10, unlockedAt: unlocked ? (date ?? Date(timeIntervalSince1970: 0)) : nil,
            isNew: isNew
        )
    }
}
