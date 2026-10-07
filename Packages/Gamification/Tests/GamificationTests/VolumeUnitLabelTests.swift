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

    func testBigGulpDescribedInOunces() {
        let env = GameEnv()
        env.addIntakeEvent(500)
        env.profiles.profile().volumeUnit = .usFluidOunces
        let gulp = env.game.achievementSnapshots().first { $0.key == "big.gulp" }!
        XCTAssertEqual(gulp.details, "34 oz за один раз")
        XCTAssertEqual(gulp.valueLabel, "17 / 34")

        env.profiles.profile().volumeUnit = .milliliters
        XCTAssertEqual(env.game.achievementSnapshots().first { $0.key == "big.gulp" }!.details, "1 л за один раз")
    }
}
