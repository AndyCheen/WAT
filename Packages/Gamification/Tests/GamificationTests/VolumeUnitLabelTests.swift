import XCTest
import Core
import Persistence
@testable import Gamification

/// Підписи об'ємних завдань і досягнень у системі людини (WAT-46). Мілілітри — як були.
@MainActor
final class VolumeUnitLabelTests: XCTestCase {
    func testVolumeQuestLabelInOunces() {
        var quest = QuestSnapshot(id: UUID(), key: "daily.morning", title: "Випити воду зранку", scope: .daily,
                                  progress: 120, target: 200, isDone: false, rewardXp: 25)
        XCTAssertEqual(quest.progressLabel, "120/200")
        quest.ounces = .usFluidOunces
        XCTAssertEqual(quest.progressLabel, "4/7")
    }

    /// Сервіс позначає лише об'ємні завдання: лічильник записів лишається «1/4».
    func testServiceMarksOnlyVolumeQuests() {
        let env = GameEnv()
        _ = env.addIntake(120, hour: 9)
        env.profiles.profile().volumeUnit = .usFluidOunces
        let quests = env.game.dailyQuests()
        XCTAssertEqual(quests.first { $0.key == "daily.goal" }?.ounces, .usFluidOunces)
        XCTAssertNil(quests.first { $0.key == "daily.entries4" }?.ounces)
        XCTAssertEqual(quests.first { $0.key == "daily.entries4" }?.progressLabel, "1/4")

        env.profiles.profile().volumeUnit = .milliliters
        XCTAssertNil(env.game.dailyQuests().first { $0.key == "daily.goal" }?.ounces)
    }

    /// Прогрес об'ємних досягнень — в унціях; опис із числом — лише в драбини «води загалом» (WAT-58:
    /// у каталозі WAT-24 «Великий ковток» — «Літрова пляшка», без числа, тож опис лишається).
    func testVolumeAchievementsInOunces() {
        let env = GameEnv()
        env.addIntakeEvent(500)
        env.profiles.profile().volumeUnit = .usFluidOunces
        let items = env.game.achievementSnapshots()
        let gulp = items.first { $0.key == "big.gulp" }!
        XCTAssertEqual(gulp.details, "Літрова пляшка одним записом")
        XCTAssertEqual(gulp.valueLabel, "17 / 34")
        XCTAssertEqual(items.first { $0.key == "volume.10l" }!.details, "338 унц. води загалом")
        XCTAssertNil(items.first { $0.key == "portions.10" }!.ounces, "порції — штуки")

        env.profiles.profile().volumeUnit = .milliliters
        let metric = env.game.achievementSnapshots()
        XCTAssertEqual(metric.first { $0.key == "volume.10l" }!.details, "10 л води загалом")
        XCTAssertEqual(metric.first { $0.key == "big.gulp" }!.valueLabel, "500 / 1000")
    }
}
