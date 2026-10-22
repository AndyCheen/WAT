import XCTest
import Core
import Persistence
@testable import Gamification

/// Каталог завдань — SPEC-QUESTS §3. Назви й довжини — `QuestPresenterTests` у `Features`: їх складає презентер.
final class QuestCatalogTests: XCTestCase {
    func testKeysAreUnique() {
        let keys = QuestCatalog.all.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testActiveQuestsHaveSlotAndDifficulty() {
        for quest in QuestCatalog.active {
            XCTAssertNotNil(quest.slot, quest.key)
            XCTAssertNotNil(quest.difficulty, quest.key)
            XCTAssertEqual(quest.legacyXp, 0, "XP чинних — з `XPRules`: \(quest.key)")
        }
    }

    func testCatalogMatchesSpec() {
        XCTAssertEqual(QuestCatalog.tempo.map(\.key),
                       ["daily.quarterBy", "daily.halfBy", "daily.threeQuartersBy", "daily.goalBy", "daily.goalNoReminders"])
        XCTAssertEqual(QuestCatalog.rhythmSlot.map(\.key),
                       ["daily.wakeGlass", "daily.glasses", "daily.glassesBy", "daily.closeBlock", "daily.everyBlock",
                        "daily.allBlocks"])
        XCTAssertEqual(QuestCatalog.starter.count, 3)
        XCTAssertEqual(QuestCatalog.steady.count + QuestCatalog.habit.count, 8, "Т1–Т8")
        let difficulty = { (key: String) in QuestCatalog.definition(key)?.difficulty?.difficulty(count: nil) }
        XCTAssertEqual(difficulty("daily.quarterBy"), .easy)
        XCTAssertEqual(difficulty("daily.goalNoReminders"), .hard)
        XCTAssertEqual(difficulty("daily.allBlocks"), .hard)
        XCTAssertEqual(QuestCatalog.definition("daily.goalNoReminders")?.requirements,
                       QuestRequirements(reminders: true, minLevel: 5))
    }

    /// Т1: N ≤ 3 — легке, 4–5 — середнє, 6 — складне; Т2: 3 — середнє, від 4 — складне (§3.4).
    func testDifficultyFromCount() {
        let goalDays = QuestCatalog.definition("weekly.goalDays")!.difficulty!
        XCTAssertEqual([3, 4, 5, 6].map(goalDays.difficulty(count:)), [.easy, .medium, .medium, .hard])
        let run = QuestCatalog.definition("weekly.goalRun")!.difficulty!
        XCTAssertEqual([3, 4, 5].map(run.difficulty(count:)), [.medium, .hard, .hard])
    }

    func testXpFromRules() {
        let rules = XPRules.default
        XCTAssertEqual(QuestDifficulty.allCases.map { rules.questXp(scope: .daily, difficulty: $0) }, [15, 25, 40])
        XCTAssertEqual(QuestDifficulty.allCases.map { rules.questXp(scope: .weekly, difficulty: $0) }, [75, 100, 150])
        XCTAssertEqual(rules.questXpRange(.daily), 15...40)
        XCTAssertEqual(rules.questXpRange(.weekly), 75...150)
    }

    /// Архівні не видаються, але визначення знаходиться: інстанси дня оновлення доживають (§3.7).
    func testRetiredKeysStayFindable() {
        let retired = ["daily.goal", "daily.entries4", "daily.morning", "weekly.streak7", "weekly.goal5days"]
        XCTAssertEqual(QuestCatalog.retired.map(\.key), retired)
        for key in retired {
            XCTAssertTrue(QuestCatalog.definition(key)!.isRetired)
            XCTAssertFalse(QuestCatalog.active.contains { $0.key == key })
            XCTAssertGreaterThan(QuestCatalog.definition(key)!.legacyXp, 0)
        }
    }
}
