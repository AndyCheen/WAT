import XCTest
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
import DesignSystem
@testable import Features

/// Вікно відкриття (WAT-60, SPEC-ACHIEVEMENTS §8): коли показується, що на сторінках, що чекає паузи.
@MainActor
final class CelebrationFeatureTests: XCTestCase {
    private var services: AppServices!
    private var clock: FixedClock!

    override func setUp() async throws {
        try await super.setUp()
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18; c.hour = 10
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        clock = FixedClock(now: cal.date(from: c)!)
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock)
        services.bootstrap()
    }

    private var shownTitles: [String] { services.celebration?.pages.map(\.title) ?? [] }

    private static var choiceLevel: Int {
        (2...60).first { if case .choice? = LevelRoadCatalog.node(forLevel: $0) { return true } else { return false } }!
    }

    // MARK: - Рівень

    /// Лише рівень, без досягнень, — тост, як і був (SPEC-PRIZES §16.6).
    func testLevelWithoutAchievementsIsAToast() {
        let model = HomeViewModel(services: services)
        model.add(200)
        services.dismissCelebration()
        let before = model.level.level
        boostXp()

        model.add(200)
        XCTAssertGreaterThan(model.level.level, before)
        XCTAssertNil(services.celebration)
        XCTAssertTrue(model.toast?.message.hasPrefix("Рівень \(model.level.level)!") ?? false, model.toast?.message ?? "тоста немає")
    }

    /// Віха й рівень однієї дії — одне свято: рівень — рядок на останній сторінці, а не окремий тост (§8.1).
    func testLevelFromTheSameActionIsARowInTheWindow() {
        boostXp()
        let model = HomeViewModel(services: services)
        model.add(200)

        XCTAssertEqual(shownTitles, ["Перша крапля"])
        XCTAssertEqual(services.celebration?.level?.number, model.level.level)
        XCTAssertNil(model.toast, "тост рівня не дублює вікно")
    }

    /// Знятий відкатом і досягнутий знову рівень удруге не святкується (побічна знахідка WAT-60).
    func testLevelRegainedAfterUndoIsNotCelebratedAgain() {
        let model = HomeViewModel(services: services)
        model.add(200)
        services.dismissCelebration()
        boostXp()
        let earlier = Set(model.history.map(\.id))

        model.add(200)
        let level = model.level.level
        XCTAssertEqual(model.toast?.message.hasPrefix("Рівень \(level)!"), true)
        model.dismissToast()
        model.remove(id: model.history.first { !earlier.contains($0.id) }!.id)
        model.dismissToast()
        XCTAssertLessThan(model.level.level, level, "відкат порції знімає рівень")

        model.add(200)
        XCTAssertEqual(model.level.level, level)
        XCTAssertNil(model.toast, "рівень \(level) уже святкували")
        XCTAssertNotEqual(model.pulse?.kind, .levelUp(level))
    }

    /// Два досягнення й рівень із вибором — дві сторінки, «Обрати приз» веде на «Шлях рівнів».
    func testLevelWithChoiceLeadsToTheLevelRoad() {
        services.gamification.xp.rules = services.gamification.xp.rules
            .applyingBalance([XPRules.BalanceKey.xpMultiplier: "0.1"])
        services.hydration.addIntake(amountMl: 1000)
        services.presentCelebrations(context: .action, level: Self.choiceLevel)

        let window = services.celebration
        XCTAssertEqual(window?.pages.count, 2)
        XCTAssertEqual(window?.level?.number, Self.choiceLevel)
        XCTAssertTrue(window?.level?.caption?.hasPrefix("Обери приз:") ?? false)
        XCTAssertEqual(window?.finishTitle, "Обрати приз")
        XCTAssertEqual(window?.laterTitle, "Пізніше")

        services.dismissCelebration()
        XCTAssertEqual(services.router.takePath(), [.levelRoad])
    }

    func testLaterKeepsTheUserWhereTheyAre() {
        services.hydration.addIntake(amountMl: 200)
        services.presentCelebrations(context: .action, level: Self.choiceLevel)
        services.dismissCelebration(later: true)
        XCTAssertNil(services.router.takePath())
        XCTAssertFalse(services.hasPendingCelebrations, "«Пізніше» теж відсвятковує")
    }

    // MARK: - Черга й паузи (§8.5)

    /// Порція з віджета, поки застосунку немає на екрані, — вікно «Поки тебе не було» на відкритті.
    func testOpeningTheAppShowsWhatHappenedWhileAway() async {
        services.handleBecameActive()
        await services.handleEnteredBackground()
        await services.perform(.add(ml: 250, source: .widget)).value
        XCTAssertNil(services.celebration, "застосунку немає на екрані — вікна теж")

        services.handleBecameActive()
        XCTAssertEqual(shownTitles.first, "Перша крапля")
        XCTAssertTrue(shownTitles.contains("На робочому столі"), "порція з віджета — ще й «Відкриття»")
        XCTAssertEqual(services.celebration?.context, .whileAway)
        XCTAssertEqual(services.celebration?.pages.first?.label, "Поки тебе не було")
    }

    /// Вбитий застосунок черги не губить: вона в базі.
    func testQueueSurvivesRelaunch() {
        services.hydration.addIntake(amountMl: 200)
        let relaunched = AppServices(container: services.container, clock: clock)
        relaunched.bootstrap()
        XCTAssertEqual(relaunched.celebration?.pages.map(\.title), ["Перша крапля"])
    }

    /// Під шторкою чи «Склянкою» вікно чекає, поки вони закриються.
    func testSheetPausesTheWindow() {
        let model = HomeViewModel(services: services)
        model.openGlass()
        model.confirmGlass()
        XCTAssertNil(services.celebration, "поверх «Склянки» — ні")
        model.dismissSheet()
        XCTAssertEqual(shownTitles, ["Перша крапля"])
        XCTAssertEqual(services.celebration?.context, .action)
    }

    /// Порція через «Інше» — вікно після шторки, з рівнем тієї самої дії.
    func testCustomPortionCelebratesAfterTheSheet() {
        boostXp()
        let model = HomeViewModel(services: services)
        model.openCustom()
        model.customAmount = 300
        model.confirmCustom()
        XCTAssertEqual(shownTitles, ["Перша крапля", "Своя мірка"])
        XCTAssertNotNil(services.celebration?.level, "рівень дії дочекався шторки разом із вікном")
    }

    func testPausesNestAndOnlyTheLastEndShows() {
        services.beginCelebrationPause(.report)
        services.beginCelebrationPause(.onboarding)
        services.record(.xpGuideOpened)
        services.endCelebrationPause(.report)
        XCTAssertNil(services.celebration, "онбординг ще відкритий")
        services.endCelebrationPause(.onboarding)
        XCTAssertEqual(shownTitles, ["Вивести на чисту воду"])
    }

    /// Кінець паузи показує й те, що вікна не просило: дочитана історія «Знань» відкриває досягнення мовчки.
    func testLearnStoryCelebratesAfterClosing() {
        let model = LearnStoryModel(services: services, storyId: "app.start", startSlide: nil)
        model.appeared()
        model.finish()
        XCTAssertNil(services.celebration)
        model.disappeared()
        XCTAssertEqual(shownTitles, ["Цікавинка"])
    }

    func testSystemPermissionRequestPausesTheWindow() async {
        let center = InMemoryNotificationCenter(status: .notDetermined)
        let services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)
        services.bootstrap()
        services.hydration.addIntake(amountMl: 200)
        services.beginCelebrationPause(.permissionRequest)
        XCTAssertTrue(services.presentCelebrations(context: .action), "є що святкувати — чекає")
        XCTAssertNil(services.celebration)
        await services.requestNotificationAuthorization()
        XCTAssertEqual(services.celebration?.pages.map(\.title), ["Перша крапля"])
    }

    /// Демо-історія й сіди e2e — відсвятковані: вікно не перекриває перший кадр сценарію.
    func testDemoSeedIsAlreadyCelebrated() {
        FixtureSeeder.seed(into: services, days: 20)
        XCTAssertNil(services.celebration)
        XCTAssertFalse(services.hasPendingCelebrations)
        XCTAssertGreaterThanOrEqual(services.profile.highestCelebratedLevel, services.gamification.levelProgress().level)
    }

    // MARK: - Презентер (§8.2–§8.4)

    func testNextStepNeedsTenPercent() {
        let three = snapshot("streak.3", value: 3, unlocked: true)
        XCTAssertEqual(CelebrationPresenter.nextLine(after: three, all: [three, snapshot("streak.7", value: 3)]),
                       "Далі: ⭐ Тиждень поспіль · 3 / 7")
        let first = snapshot("first.drop", value: 1, unlocked: true)
        let all = [first] + AchievementCatalog.higherSteps(after: "first.drop").map { snapshot($0.key, value: 1) }
        XCTAssertNil(CelebrationPresenter.nextLine(after: first, all: all), "1 / 100 лякає, а не заохочує")
    }

    func testNextStepSkipsUnlockedAndGated() {
        let three = snapshot("streak.3", value: 7, unlocked: true)
        let seven = snapshot("streak.7", value: 7, unlocked: true)
        let line = CelebrationPresenter.nextLine(after: three, all: [three, seven, snapshot("streak.14", value: 7)])
        XCTAssertEqual(line?.hasPrefix("Далі: "), true)
        XCTAssertTrue(line?.contains("7 / 14") ?? false, line ?? "рядка немає")

        let morning = snapshot("rhythm.morning", value: 10, unlocked: true)
        let gated = AchievementCatalog.higherSteps(after: "rhythm.morning").map {
            snapshot($0.key, value: 10, caption: "Увімкни «Ритм дня» в налаштуваннях")
        }
        XCTAssertNil(CelebrationPresenter.nextLine(after: morning, all: [morning] + gated), "функцію вимкнено — сходинки немає")
    }

    func testMoreThanThreeBecomeOneGridPage() {
        let items = ["first.drop", "day.goal", "big.gulp", "streak.3"].map { snapshot($0, value: 1, unlocked: true) }
        let window = CelebrationPresenter.make(items, all: items, context: .whileAway, level: nil)
        XCTAssertEqual(window?.pages.count, 1)
        XCTAssertEqual(window?.pages.first?.title, "Нові досягнення: 4")
        XCTAssertEqual(window?.pages.first?.grid.count, 4)
        XCTAssertEqual(window?.pages.first?.xp, items.map(\.rewardXp).reduce(0, +))
        XCTAssertEqual(window?.keys, items.map(\.key))

        let three = CelebrationPresenter.make(Array(items.prefix(3)), all: items, context: .action, level: nil)
        XCTAssertEqual(three?.pages.count, 3, "до трьох — сторінки з «Далі»")
    }

    /// Підписи — на «ти» й без роду; VoiceOver чує все одним рядком (§8.8, CLAUDE.md).
    func testTextsAreGenderNeutral() {
        let all = services.gamification.achievementSnapshots()
        let gendered = ["пив ", "пила", "випив ", "випила", "відкрив ", "відкрила", "зробив ", "зробила", "знайшов", "знайшла"]
        for definition in AchievementCatalog.active {
            let item = snapshot(definition.key, value: definition.target, unlocked: true)
            for context in [Celebration.Context.action, .whileAway] {
                let page = CelebrationPresenter.page(item, all: all, context: context)
                let text = [page.label, page.title, page.details, page.next ?? "", page.accessibilityLabel].joined(separator: " ")
                for word in gendered { XCTAssertFalse(text.lowercased().contains(word), "\(definition.key): \(text)") }
                XCTAssertTrue(page.accessibilityLabel.hasPrefix("\(page.label): \(definition.title). "))
                XCTAssertTrue(page.accessibilityLabel.hasSuffix("Плюс \(definition.rewardXp) XP"))
            }
        }
        let caption = CelebrationPresenter.levelCaption(LevelRoadCatalog.node(forLevel: Self.choiceLevel))
        XCTAssertEqual(caption?.hasPrefix("Обери приз: "), true)
    }

    // MARK: - Допоміжне

    /// XP за воду щедрий — одна порція піднімає рівень, а XP досягнень (і з ним «Річка», «Море») — звичайний.
    private func boostXp() {
        services.gamification.xp.rules = services.gamification.xp.rules
            .applyingBalance([XPRules.BalanceKey.xpPerVolumeStep: "300"])
    }

    private func snapshot(_ key: String, value: Double, unlocked: Bool = false, caption: String? = nil) -> AchievementSnapshot {
        let definition = AchievementCatalog.definition(key)!
        return AchievementSnapshot(
            key: key, title: definition.title, details: definition.details, emoji: definition.emoji,
            category: definition.category, value: value, target: definition.target, isUnlocked: unlocked,
            isSecret: definition.isSecret, rewardXp: definition.rewardXp, isEgg: definition.secrecy.isEgg,
            lockedCaption: caption
        )
    }
}

extension CelebrationFeatureTests {
    /// Порцію скасували, поки вікно на екрані (віджет у фоні), — на відкритті вікно без знятого.
    func testRevertedWhileShownLeavesTheWindow() {
        let model = HomeViewModel(services: services)
        model.add(200)
        XCTAssertEqual(services.celebration?.pages.map(\.title), ["Перша крапля"])
        _ = services.hydration.removeIntake(id: model.history.first!.id)
        services.handleBecameActive()
        XCTAssertNil(services.celebration, "«Першої краплі» більше немає — і святкувати нічого")
    }
}
