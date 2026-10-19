import XCTest
import Core
import Persistence
@testable import Gamification

/// Каталог проти `SPEC-ACHIEVEMENTS-CATALOG.md`: числа з §2–§4, ключі наявних, XP за таблицею, тексти.
@MainActor
final class AchievementCatalogTests: XCTestCase {
    private let all = AchievementCatalog.all

    func testCatalogMatchesTheSpecCounts() {
        XCTAssertEqual(all.count, 118, "115 досягнень без «Бульк!» (§8) + 3 за «Знання» (SPEC-LEARN §7)")
        XCTAssertEqual(Set(all.map(\.key)).count, all.count, "ключі унікальні")
        XCTAssertEqual(all.filter { $0.secrecy.isEgg }.count, 10, "пасхалки — §4.10")
        XCTAssertEqual(all.filter { if case .hint = $0.secrecy { return true } else { return false } }.count, 16,
                       "таємні з підказкою — §4.9")
        XCTAssertEqual(all.filter { $0.gate == .dayRhythm }.count, 4)
        XCTAssertEqual(all.filter { $0.gate == .notifications }.count, 6)
        XCTAssertEqual(all.filter(\.isCore).count, 82, "основний каталог — 82 із 118 (§4.6)")

        let byCategory = Dictionary(grouping: all.filter { !$0.secrecy.isEgg }, by: \.category).mapValues(\.count)
        XCTAssertEqual(byCategory, [
            .water: 14, .streak: 13, .regularity: 10, .dayRhythm: 10,
            .stats: 6, .game: 17, .discovery: 18, .special: 20
        ])

        let byDifficulty = Dictionary(grouping: all, by: \.difficulty).mapValues(\.count)
        XCTAssertEqual(byDifficulty, [.easy: 54, .medium: 40, .hard: 15, .legendary: 9], "§2 + SPEC-LEARN §7")
    }

    /// Ключі наявних семи не змінюються — за ключем зберігається прогрес; назви й описи — за §7, п. 2.
    func testExistingKeysKeepProgressWithNewTexts() {
        let expected: [String: (String, String)] = [
            "first.drop": ("Перша крапля", "Перший запис води"),
            "day.goal": ("Ціль дня", "Випито денну норму"),
            "big.gulp": ("Великий ковток", "Літрова пляшка одним записом"),
            "streak.3": ("3 дні поспіль", "3 дні поспіль із нормою"),
            "streak.7": ("Тиждень поспіль", "7 днів поспіль із нормою"),
            "streak.30": ("Місяць витримки", "30 днів поспіль із нормою"),
            "marathon": ("Марафон", "20 днів із нормою")
        ]
        for (key, texts) in expected {
            let definition = AchievementCatalog.definition(key)
            XCTAssertEqual(definition?.title, texts.0, key)
            XCTAssertEqual(definition?.details, texts.1, key)
        }
    }

    /// XP поки за таблицею §2 — остаточні числа в WAT-25.
    func testRewardFollowsDifficultyTable() {
        for definition in all {
            let expected: Int
            switch definition.difficulty {
            case .easy: expected = definition.category == .discovery ? 15 : 25
            case .medium: expected = 100
            case .hard: expected = 300
            case .legendary: expected = 1000
            }
            XCTAssertEqual(definition.rewardXp, expected, definition.key)
        }
    }

    /// «Усе зібрано» — решта основного каталогу, без себе.
    func testCompleteCatalogTargetsTheRestOfTheCore() {
        let complete = AchievementCatalog.definition("collection.all")
        XCTAssertEqual(complete?.target, 81, "78 + 3 за «Знання» (SPEC-LEARN §7)")
        XCTAssertEqual(complete?.isCore, true)
    }

    /// Колекції — останніми в проході, щоб бачити відкрите тут же.
    func testCollectionsAreEvaluatedLast() {
        let order = AchievementCatalog.evaluationOrder.map(\.key)
        XCTAssertEqual(Array(order.suffix(4)), ["collection.10", "collection.25", "collection.50", "collection.all"])
    }

    /// Тексти на «ти» й без родового минулого часу (CLAUDE.md, SPEC-NOTIFICATIONS §14.1).
    func testTextsHaveNoGenderedPastTense() {
        let gendered: Set<String> = [
            "пив", "пила", "випив", "випила", "забув", "забула", "зробив", "зробила", "закрив", "закрила",
            "почав", "почала", "був", "була", "записав", "записала", "пропустив", "пропустила", "відкрив", "відкрила",
            "знайшов", "знайшла", "зібрав", "зібрала"
        ]
        for definition in all {
            var texts = [definition.title, definition.details]
            if case .hint(let hint) = definition.secrecy { texts.append(hint) }
            for text in texts {
                let words = Set(text.lowercased().split { !$0.isLetter && $0 != "'" && $0 != "ʼ" }.map(String.init))
                XCTAssertTrue(words.isDisjoint(with: gendered), "«\(text)»")
                XCTAssertFalse(words.contains("ви") || words.contains("ваш"), "«ви» у «\(text)»")
            }
        }
    }

    /// Пасхалки й таємні не вибиваються з основного каталогу, а залежні від функцій — не таємні.
    func testGatedAreNeverSecret() {
        XCTAssertTrue(all.filter { $0.gate != nil }.allSatisfy { $0.secrecy == .none })
    }
}
