import XCTest
import SwiftData
import Core
import Persistence
import Gamification
@testable import Features

/// Розділ «Знання» (WAT-53, SPEC-LEARN): каталог проти ТЗ, правила текстів, живі значення, прогрес і досягнення.
@MainActor
final class LearnFeatureTests: XCTestCase {
    private var services: AppServices!

    override func setUp() async throws {
        try await super.setUp()
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 19; c.hour = 10
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        services = AppServices(container: Database.makeInMemoryContainer(), clock: FixedClock(now: cal.date(from: c)!))
        services.bootstrap()
    }

    private func slides(_ id: String, context: LearnContext? = nil) -> [LearnSlide] {
        LearnPresenter(context: context ?? services.learnContext()).slides(for: LearnCatalog.story(id)!)
    }

    // MARK: - Каталог (§4)

    func testCatalogMatchesThePlan() {
        let stories = LearnCatalog.stories
        XCTAssertEqual(stories.count, 12, "12 історій — рішення від 19.10.2026")
        XCTAssertEqual(Set(stories.map(\.id)).count, stories.count, "ідентифікатор — ключ прогресу, унікальний")
        XCTAssertEqual(LearnShelf.allCases.map { LearnCatalog.stories(in: $0).count }, [4, 3, 5])
    }

    /// Досягнення «вся полиця» рахують різні дочитані історії — ціль мусить дорівнювати кількості на полиці.
    func testShelfAchievementsTargetWholeShelf() {
        XCTAssertEqual(AchievementCatalog.definition("discover.learnWater")?.target,
                       Double(LearnCatalog.stories(in: .body).count))
        XCTAssertEqual(AchievementCatalog.definition("discover.learnApp")?.target,
                       Double(LearnCatalog.stories(in: .app).count))
    }

    func testEveryStoryHasFiveToSevenSlidesAndEndsWithAnAction() {
        for story in LearnCatalog.stories {
            let slides = slides(story.id)
            XCTAssertTrue((5...7).contains(slides.count), "\(story.id): \(slides.count) слайдів (§5.1)")
            XCTAssertEqual(slides.first?.kind, .cover, story.id)
            switch slides.last?.kind {
            case .action, .quizScore: break
            default: XCTFail("\(story.id): остання — «Що з цим робити» з кнопкою (§4)")
            }
        }
    }

    /// Кожен факт полиці «Вода й тіло» — з першоджерелом, і воно є у списку на фініші (§5.3).
    func testHealthFactsHaveSources() {
        for story in LearnCatalog.stories {
            for slide in slides(story.id) {
                if let source = slide.source {
                    XCTAssertTrue(story.sources.contains(source), "\(story.id): «\(slide.title)» — \(source) немає на фініші")
                }
                guard story.shelf == .body else { continue }
                switch slide.kind {
                case .fact, .list, .quiz:
                    XCTAssertNotNil(slide.source, "\(story.id): «\(slide.title)» без джерела")
                default:
                    break
                }
            }
        }
    }

    // MARK: - Тексти (§5.2)

    func testCopyFitsTheTemplates() {
        for story in LearnCatalog.stories {
            for slide in slides(story.id) {
                XCTAssertLessThanOrEqual(slide.kicker.count, 24, "\(story.id): надзаголовок «\(slide.kicker)»")
                XCTAssertLessThanOrEqual(slide.title.count, 48, "\(story.id): заголовок «\(slide.title)»")
                if let text = slide.text {
                    XCTAssertLessThanOrEqual(text.count, 140, "\(story.id): текст «\(text)»")
                }
                if case .quiz(_, let explanation) = slide.kind {
                    XCTAssertLessThanOrEqual(explanation.count, 140, "\(story.id): пояснення «\(explanation)»")
                }
                XCTAssertLessThanOrEqual(slide.items.count, 4, "\(story.id): ≤ 4 пункти")
            }
        }
    }

    /// На «ти» й без роду (SPEC-NOTIFICATIONS §14.1): ні «пив / пила», ні «готовий / готова».
    func testCopyIsGenderNeutral() {
        let forbidden: Set<String> = ["пив", "пила", "випив", "випила", "готовий", "готова", "зроблений", "зроблена",
                                      "міняв", "міняла", "помилився", "помилилась", "забув", "забула", "сам", "сама",
                                      "радий", "рада"]
        for story in LearnCatalog.stories {
            for line in slides(story.id).flatMap(\.copy) {
                // Цілими словами: «порада» не «рада».
                let words = Set(line.lowercased().split { !$0.isLetter }.map(String.init))
                XCTAssertTrue(words.isDisjoint(with: forbidden), "\(story.id): «\(line)»")
            }
        }
    }

    /// Емодзі — лише як іконка пункту, не посеред заголовка чи тексту.
    func testNoEmojiInsideSentences() {
        for story in LearnCatalog.stories {
            for slide in slides(story.id) {
                for line in [slide.kicker, slide.title] + [slide.text].compactMap({ $0 }) {
                    let emoji = line.unicodeScalars.filter { $0.properties.isEmojiPresentation }
                    XCTAssertTrue(emoji.isEmpty, "\(story.id): «\(line)»")
                }
            }
        }
    }

    // MARK: - Живі значення (§5.4)

    func testXpStoryFollowsBalance() {
        var context = services.learnContext()
        context.rules.xpPerVolumeStep = 10
        context.rules.volumeStepMl = 200
        context.rules.xpMultiplier = 2
        let water = slides("app.xp", context: context)[1]

        XCTAssertEqual(water.title, "За кожні 200 мл — а не за натискання")
        XCTAssertEqual(water.number?.value, 20, "крок × загальний множник — як у довіднику «Звідки XP»")
        guard case let .glasses(full, bonus, _, chip, _)? = water.visual else { return XCTFail("склянки") }
        XCTAssertEqual(full, 10, "2000 мл / 200")
        XCTAssertEqual(bonus, 2, "до 120 % — ще 400 мл")
        XCTAssertEqual(chip, "+20")
    }

    func testLevelRoadSummaryNamesTheNextPrize() {
        var context = services.learnContext()
        context.level = 7
        let action = slides("app.xp", context: context).last
        XCTAssertEqual(action?.text, "Ти на 7-му рівні. Наступний приз — на 8-му: заморозка серії.")
    }

    func testNormRingUsesGoalBlocks() {
        guard case let .ring(total, _, segments)? = slides("body.why").last?.visual else { return XCTFail("кільце") }
        XCTAssertEqual(total, "2000")
        XCTAssertEqual(segments.map(\.value).compactMap(Int.init).reduce(0, +), 2000, "цілі блоків складаються в норму")
        XCTAssertEqual(segments.count, services.learnContext().blocks.count)
    }

    func testRhythmOffShowsSingleGoal() {
        services.profile.dayRhythmEnabled = false
        guard case let .ring(_, _, segments)? = slides("body.why").last?.visual else { return XCTFail("кільце") }
        XCTAssertEqual(segments.count, 1, "без «Ритму дня» — просто норма (WAT-42)")
        XCTAssertFalse(slides("app.xp")[2].items.contains { $0.emoji == "⏰" })
    }

    // MARK: - Прогрес (§6)

    func testFirstVisitShowsNoNewBadgesAndClearsHomeDot() {
        XCTAssertTrue(services.hasLearnNews, "до першого відкриття крапка горить")
        let library = LearnLibraryModel(services: services)
        library.reload()

        XCTAssertFalse(library.shelves.flatMap(\.entries).contains { $0.badge == .new },
                       "«Нове» на всіх 12 — шум, а не новина")
        XCTAssertFalse(services.hasLearnNews)
    }

    func testUnfinishedStoryResumesWhereItStopped() {
        let story = LearnStoryModel(services: services, storyId: "body.why")
        story.slideIndex = 3

        let library = LearnLibraryModel(services: services)
        library.reload()
        XCTAssertEqual(library.resume?.story.id, "body.why")
        XCTAssertEqual(library.resume?.slide, 3)
        XCTAssertEqual(LearnStoryModel(services: services, storyId: "body.why").slideIndex, 3)
    }

    func testFinishMarksReadAndRestartsFromCover() {
        let story = LearnStoryModel(services: services, storyId: "app.xp")
        story.slideIndex = story.count - 1

        XCTAssertEqual(services.learn.progress("app.xp")?.isCompleted, true)
        XCTAssertEqual(LearnStoryModel(services: services, storyId: "app.xp").slideIndex, 0, "прочитана — з початку")
        let library = LearnLibraryModel(services: services)
        library.reload()
        XCTAssertEqual(library.shelves.flatMap(\.entries).first { $0.id == "app.xp" }?.badge, .read)
    }

    func testQuizScoreCountsCorrectAnswers() {
        let story = LearnStoryModel(services: services, storyId: "body.myths")
        story.answer(false, at: 1)
        story.answer(true, at: 2)
        story.answer(false, at: 2)
        XCTAssertEqual(story.correctAnswers, 1, "друга відповідь на той самий слайд не рахується")
        XCTAssertEqual(story.quizCount, 5)
    }

    // MARK: - Досягнення (§7)

    func testReadingUnlocksAchievementsWithoutXpPerStory() {
        let xpBefore = services.gamification.levelProgress().totalXp
        for story in LearnCatalog.stories(in: .body) {
            let model = LearnStoryModel(services: services, storyId: story.id)
            model.slideIndex = model.count - 1
        }
        // Перечитана історія лічильник не збільшує.
        let again = LearnStoryModel(services: services, storyId: "body.why")
        again.slideIndex = again.count - 1

        let unlocked = Set(services.gamification.achievementSnapshots().filter(\.isUnlocked).map(\.key))
        XCTAssertTrue(unlocked.isSuperset(of: ["discover.learn", "discover.learnWater"]))
        XCTAssertFalse(unlocked.contains("discover.learnApp"))
        let achievementXp = ["discover.learn", "discover.learnWater"]
            .compactMap { AchievementCatalog.definition($0)?.rewardXp }.reduce(0, +)
        XCTAssertEqual(services.gamification.levelProgress().totalXp - xpBefore, achievementXp,
                       "XP — лише за досягнення, не за кожну історію")
    }
}
