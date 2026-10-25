import XCTest
import Core
import Persistence
@testable import Gamification

/// Каталог проти `SPEC-ACHIEVEMENTS-CATALOG.md`: числа з §2–§4, ключі наявних, XP за таблицею, тексти.
@MainActor
final class AchievementCatalogTests: XCTestCase {
    /// Чинний каталог — без знятих з WAT-60 (§10.2): вони лишаються визначеннями лише для тих, хто їх уже має.
    private let all = AchievementCatalog.active

    func testCatalogMatchesTheSpecCounts() {
        XCTAssertEqual(AchievementCatalog.all.count, 119, "115 без «Бульк!» (§8) + 3 за «Знання» + «Несподіванка», зі знятими")
        XCTAssertEqual(AchievementCatalog.all.filter(\.isRetired).count, 7, "§10.1")
        XCTAssertEqual(all.count, 112, "§10.4: разом із «Несподіванкою» (WAT-65)")
        XCTAssertEqual(Set(AchievementCatalog.all.map(\.key)).count, AchievementCatalog.all.count, "ключі унікальні")
        XCTAssertEqual(all.filter { $0.secrecy.isEgg }.count, 10, "пасхалки — §4.10")
        XCTAssertEqual(all.filter { if case .hint = $0.secrecy { return true } else { return false } }.count, 16,
                       "таємні з підказкою — §4.9")
        XCTAssertEqual(all.filter { $0.gate == .dayRhythm }.count, 4)
        XCTAssertEqual(all.filter { $0.gate == .notifications }.count, 5)
        XCTAssertEqual(all.filter { $0.gate == .surpriseQuests }.map(\.key), ["quest.firstSurprise"])
        XCTAssertEqual(all.filter(\.isCore).count, 76, "основний каталог — 76 (§10.4)")

        let byCategory = Dictionary(grouping: all.filter { !$0.secrecy.isEgg }, by: \.category).mapValues(\.count)
        XCTAssertEqual(byCategory, [
            .water: 12, .streak: 13, .regularity: 10, .dayRhythm: 10,
            .stats: 6, .game: 16, .discovery: 15, .special: 20
        ])

        let byDifficulty = Dictionary(grouping: all, by: \.difficulty).mapValues(\.count)
        XCTAssertEqual(byDifficulty, [.easy: 42, .medium: 46, .hard: 15, .legendary: 9],
                       "§10.4: 43 легких разом із «Несподіванкою»; «Ранок, день і вечір» — середнє з WAT-67")
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

    /// Перебалансування першого тижня — таблиця §10.1 (ACHIEVEMENTS-RARITY-PLAN §1.3): ключі ті самі, пороги вищі.
    func testFirstWeekRebalanceTable() {
        let retired = ["volume.1l", "portions.10", "level.5", "mystery.first", "discover.levelChoice", "discover.undo",
                       "discover.notifications"]
        XCTAssertEqual(Set(AchievementCatalog.all.filter(\.isRetired).map(\.key)), Set(retired))

        let expected: [String: (title: String, target: Double, difficulty: AchievementDifficulty)] = [
            "volume.10l": ("Відро", 20_000, .easy),
            "rhythm.morning": ("Добрий ранок", 10, .medium),
            "rhythm.allThree": ("Ранок, день і вечір", 10, .medium),
            "rhythm.even90": ("Рівна крива", 7, .medium),
            "rhythm.responsive": ("Чуйність", 30, .medium),
            "rhythm.ahead": ("На крок попереду", 10, .medium),
            "stats.bullseye": ("В яблучко", 3, .medium),
            "stats.accuracy": ("Влучність", 10, .medium),
            "special.halfFull": ("Склянка наполовину повна", 5, .medium),
            "special.eightGlasses": ("Вісім на вісім", 8, .medium),
            "quest.allDaily": ("Без хвостів", 10, .medium),
            "quest.first": ("Тижнева мета", 1, .easy)
        ]
        for (key, row) in expected {
            let definition = AchievementCatalog.definition(key)
            XCTAssertEqual(definition?.title, row.title, key)
            XCTAssertEqual(definition?.target, row.target, key)
            XCTAssertEqual(definition?.difficulty, row.difficulty, key)
        }
        guard case .metric(let weekly)? = AchievementCatalog.definition("quest.first")?.rule,
              case .metric(let key, _, _) = weekly.source else { return XCTFail("«Тижнева мета» — лічильник") }
        XCTAssertEqual(key, .weeklyQuestCompleted)
        XCTAssertEqual(AchievementCatalog.definition("discover.dark")?.details, "Темну тему обрано в налаштуваннях")
        XCTAssertEqual(AchievementCatalog.definition("special.fullMoon")?.details, "Норма в день повного місяця")
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
        XCTAssertEqual(complete?.target, 75, "76 без себе (§10.4)")
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
