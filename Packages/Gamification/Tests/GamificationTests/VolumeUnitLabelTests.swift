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
        XCTAssertEqual(items.first { $0.key == "volume.10l" }!.details, "676 унц. води загалом")
        XCTAssertNil(items.first { $0.key == "portions.100" }!.ounces, "порції — штуки")

        env.profiles.profile().volumeUnit = .milliliters
        let metric = env.game.achievementSnapshots()
        XCTAssertEqual(metric.first { $0.key == "volume.10l" }!.details, "20 л води загалом")
        XCTAssertEqual(metric.first { $0.key == "big.gulp" }!.valueLabel, "500 / 1000")
    }

    // MARK: - Точні об'єми в унціях (WAT-59)

    /// Найменша порція — 50 мл у метричній, 2 унц. (59 мл) в унціях; 50 мл на межі степера теж «2 унц.».
    func testSmallestPortionPerSystem() {
        XCTAssertEqual(Intake.smallestMl(in: .milliliters), 50)
        XCTAssertEqual(Intake.smallestMl(in: .usFluidOunces), 59)
        XCTAssertEqual(VolumeUnit.usFluidOunces.label(Intake.smallestMl(in: .usFluidOunces)), "2 унц.")
        XCTAssertEqual(Intake.smallestAmountsMl, [50, 59])
    }

    /// «Наперсток» в унціях досяжний найменшою порцією системи, і опис — у ній же.
    func testThimbleInOunces() {
        let env = GameEnv()
        env.profiles.profile().volumeUnit = .usFluidOunces
        env.drink(VolumeUnit.usFluidOunces.milliliters(units: 3), on: "2026-07-18", hour: 9)
        XCTAssertFalse(env.isUnlocked("special.thimble"), "3 унц. — уже не ковточок")
        env.drink(VolumeUnit.usFluidOunces.milliliters(units: 2), on: "2026-07-18", hour: 10)
        XCTAssertTrue(env.isUnlocked("special.thimble"))

        let thimble = env.achievement("special.thimble")!
        XCTAssertEqual(thimble.details, "Порція 2 унц.")
        XCTAssertNil(thimble.ounces, "разове — без прогресу в унціях")

        env.profiles.profile().volumeUnit = .milliliters
        XCTAssertEqual(env.achievement("special.thimble")?.details, "Порція 50 мл")
    }

    /// Маскований «Наперсток» в унціях — та сама підказка, без об'єму.
    func testMaskedThimbleKeepsHintInOunces() {
        let env = GameEnv()
        env.profiles.profile().volumeUnit = .usFluidOunces
        XCTAssertEqual(env.achievement("special.thimble")?.details, "«Іноді досить і ковточка»")
    }

    /// «Пі» — лише метрична пасхалка: жодна ціла кількість унцій не дає 314 мл, і невидима вона лишається.
    func testPiStaysMetricOnly() {
        let ounces = VolumeUnit.usFluidOunces
        XCTAssertFalse((1...67).contains { ounces.milliliters(units: $0) == 314 })

        let env = GameEnv()
        env.profiles.profile().volumeUnit = .usFluidOunces
        for (hour, units) in [10, 11].enumerated() {
            env.drink(ounces.milliliters(units: units), on: "2026-07-18", hour: 9 + hour)
        }
        XCTAssertFalse(env.game.achievementSnapshots().contains { $0.key == "egg.pi" })
        env.drink(314, on: "2026-07-18", hour: 12)
        XCTAssertEqual(env.achievement("egg.pi")?.details, "314 мл — майже π", "опис — сам каламбур, не перекладається")
    }
}
