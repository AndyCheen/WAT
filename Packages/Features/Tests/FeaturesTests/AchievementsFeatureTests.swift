import XCTest
import SwiftData
import Core
import Persistence
import Gamification
@testable import Features

/// Модуль «Досягнення» на рівні моделей екранів: тост на головному, фільтри 2e,
/// вітрина 3f (SPEC-ACHIEVEMENTS §4, §5, §8).
@MainActor
final class AchievementsFeatureTests: XCTestCase {
    private var services: AppServices!

    override func setUp() async throws {
        try await super.setUp()
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18; c.hour = 10
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        services = AppServices(container: Database.makeInMemoryContainer(), clock: FixedClock(now: cal.date(from: c)!))
        services.bootstrap()
    }

    // MARK: - Тост (§8)

    func testFirstIntakeShowsAchievementToastThatOpensTheCard() {
        let model = HomeViewModel(services: services)
        model.add(200)

        XCTAssertEqual(model.toast?.message, "🏅 Досягнення: Перша крапля")
        XCTAssertEqual(model.toast?.action, .showAchievement("first.drop"))
        XCTAssertEqual(model.pulse?.kind, .achievementUnlocked)
        XCTAssertTrue(model.hasNewAchievements)

        model.performToastAction()

        XCTAssertEqual(model.achievementDetail?.key, "first.drop", "«Подивитись» відкриває картку одразу")
        XCTAssertFalse(model.hasNewAchievements, "крапка гасне після перегляду картки")
    }

    func testSeveralUnlocksInOneActionGiveOneToastLeadingToTheScreen() {
        let model = HomeViewModel(services: services)
        var opened = false
        model.onOpenAchievements = { opened = true }

        model.add(1000) // «Перша крапля» + «Великий ковток»

        XCTAssertEqual(model.toast?.message, "🏅 Нові досягнення: 2")
        model.performToastAction()
        XCTAssertTrue(opened, "кілька досягнень — дія веде на екран 2e")
    }

    func testIntakeWithoutUnlockGivesNoAchievementToast() {
        let model = HomeViewModel(services: services)
        model.add(200)
        model.dismissToast()

        model.add(200)
        XCTAssertNil(model.toast)
    }

    // MARK: - Екран 2e (§5, §7.4)

    func testCounterIsGlobalAndFiltersCombine() {
        services.hydration.addIntake(amountMl: 600) // «Перша крапля» відкрита, «Великий ковток» у процесі
        let model = AchievementsViewModel(services: services)

        XCTAssertEqual(model.unlockedCount, 1)
        XCTAssertEqual(model.totalCount, 7)

        model.selectState(.inProgress)
        XCTAssertEqual(model.filtered.map(\.key), ["big.gulp"])
        XCTAssertEqual(model.unlockedCount, 1, "чип стану не змінює лічильник")

        model.selectCategory(.streak)
        XCTAssertEqual(model.emptyState, .filtered)

        model.resetFilters()
        XCTAssertNil(model.category)
        XCTAssertEqual(model.stateFilter, .all)
        XCTAssertEqual(model.filtered.count, 7)
    }

    func testCategoryFilterCoversGeneralAchievements() {
        let model = AchievementsViewModel(services: services)
        model.selectCategory(.general)
        XCTAssertEqual(Set(model.filtered.map(\.key)), ["first.drop", "marathon"], "«Загальні» мають власний фільтр")
        XCTAssertFalse(model.isCategoryMenuOpen, "вибір закриває меню")
    }

    func testUnlockedFilterOnCleanInstallOffersToShowAll() {
        let model = AchievementsViewModel(services: services)
        model.selectState(.unlocked)
        XCTAssertEqual(model.emptyState, .nothingUnlocked)
    }

    func testNewDotSurvivesTheFirstVisitOnly() {
        services.hydration.addIntake(amountMl: 200)

        // `init` + `onAppear` — саме так екран проходить перший показ.
        let first = AchievementsViewModel(services: services)
        first.reload()
        XCTAssertTrue(first.items.first { $0.key == "first.drop" }!.isNew, "у цей візит крапку видно")

        let second = AchievementsViewModel(services: services)
        second.reload()
        XCTAssertFalse(second.items.first { $0.key == "first.drop" }!.isNew, "наступного разу — вже ні")
    }

    // MARK: - Вітрина 3f (§4)

    func testShowcaseIsEmptyOnCleanInstallAndSkipsUntouched() {
        let progress = ProgressViewModel(services: services)
        XCTAssertTrue(progress.achievementShowcase.isEmpty)

        services.hydration.addIntake(amountMl: 600)
        progress.reload()

        XCTAssertEqual(progress.achievementShowcase.map(\.key), ["first.drop", "big.gulp"])
    }
}
