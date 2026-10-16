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
        // XP за воду й за п'ять досягнень дав би рівень, а тост рівня важливіший. Тут перевіряємо саме
        // тост досягнень, тож увесь XP — у десять разів менший.
        services.gamification.xp.rules = services.gamification.xp.rules
            .applyingBalance([XPRules.BalanceKey.xpMultiplier: "0.1"])

        model.add(1000) // «Перша крапля», «Великий ковток», «Глечик», «Склянка наполовину повна», «Добрий ранок»

        XCTAssertEqual(model.toast?.message, "🏅 Нові досягнення: 5")
        XCTAssertEqual(model.toast?.action, .showAllAchievements)
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
        XCTAssertEqual(model.totalCount, 105, "115 без 10 пасхалок (SPEC-ACHIEVEMENTS-CATALOG §4.10)")

        model.selectState(.inProgress)
        XCTAssertTrue(model.filtered.contains { $0.key == "big.gulp" })
        XCTAssertTrue(model.filtered.allSatisfy { $0.state == .inProgress })
        XCTAssertEqual(model.unlockedCount, 1, "чип стану не змінює лічильник")

        model.selectCategory(.streak)
        XCTAssertEqual(model.emptyState, .filtered)

        model.resetFilters()
        XCTAssertNil(model.category)
        XCTAssertEqual(model.stateFilter, .all)
        XCTAssertEqual(model.filtered.count, 105)
    }

    func testCategoryFilterCoversWaterAchievements() {
        let model = AchievementsViewModel(services: services)
        model.selectCategory(.water)
        XCTAssertEqual(model.filtered.count, 14, "§4.1")
        XCTAssertTrue(model.filtered.contains { $0.key == "first.drop" })
        XCTAssertFalse(model.filtered.contains { $0.key == "marathon" }, "«Марафон» — у «Регулярності»")
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

        let showcase = progress.achievementShowcase
        XCTAssertEqual(showcase.first?.key, "first.drop", "щойно відкрите — першим")
        XCTAssertTrue(showcase.contains { $0.key == "big.gulp" })
        XCTAssertEqual(showcase.count, AchievementCatalog.showcaseLimit)
        XCTAssertFalse(showcase.contains(where: \.isMasked), "таємне у вітрину не потрапляє")
    }

    // MARK: - Таємні й пасхалки (SPEC-ACHIEVEMENTS-CATALOG §4.9–4.10)

    /// Пасхалка — свій тост, окремий лічильник «🥚 N», рядок у картці першої.
    func testEggHasItsOwnToastAndCounter() {
        let home = HomeViewModel(services: services)
        home.customAmount = 300
        home.confirmCustom()
        XCTAssertEqual(home.toast?.message, "🏅 Нові досягнення: 2", "«Перша крапля» і «Своя мірка»")
        home.dismissToast()

        home.customAmount = 314
        home.confirmCustom()
        XCTAssertEqual(home.toast?.message, "🥚 Пасхалка: Пі")

        let screen = AchievementsViewModel(services: services)
        screen.reload()
        XCTAssertEqual(screen.totalCount, 105, "знайдена пасхалка видимий каталог не роздуває")
        XCTAssertEqual(screen.eggLabel, "🥚 1")
        XCTAssertTrue(screen.counterAccessibilityValue.contains("пасхалок знайдено: 1"))
        XCTAssertEqual(screen.items.first { $0.key == "egg.pi" }?.note, "Пасхалка! Тут їх більше")
    }

    func testSecretTileAndCardShowOnlyTheHint() {
        let model = AchievementsViewModel(services: services)
        let secret = model.items.first { $0.key == "special.thimble" }!
        XCTAssertEqual(secret.title, "???")
        XCTAssertEqual(secret.tileStatus, .hidden)
        XCTAssertEqual(secret.detailStatus, .hidden, "у картці — ні умови, ні прогресу")
        XCTAssertEqual(secret.detailAccessibilityValue, "«Іноді досить і ковточка». Таємне досягнення")
        XCTAssertNil(model.eggLabel, "до першої пасхалки «🥚» немає")
    }

    func testDisabledFeatureShowsCaptionInsteadOfProgress() {
        services.profile.dayRhythmEnabled = false
        let model = AchievementsViewModel(services: services)
        XCTAssertEqual(model.items.first { $0.key == "rhythm.morning" }?.tileStatus,
                       .caption("Увімкни «Ритм дня» в налаштуваннях"))
    }

    // MARK: - Тост поза головним

    /// Після оновлення досягнення відкриваються з історії — один тост на всі (SPEC-ACHIEVEMENTS-CATALOG §6).
    func testUpdateBackfillsFromHistoryWithOneToast() {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18; c.hour = 10
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let updated = AppServices(container: Database.makeInMemoryContainer(), clock: FixedClock(now: cal.date(from: c)!))
        for offset in 1...6 {
            let day = updated.calendar.dayKey(offsetDays: -offset, from: updated.calendar.today)
            let log = updated.dayLogs.dayLog(for: day, goalMl: 2000, timeZoneId: "Europe/Kyiv")
            log.totalMl = 2000
            log.countedMl = 2000
            log.entriesCount = 4
        }
        updated.dayLogs.save()

        updated.bootstrap()
        XCTAssertTrue(updated.unlockAnnouncement?.message.hasPrefix("🏅 Нові досягнення:") ?? false,
                      updated.unlockAnnouncement?.message ?? "тоста немає")
        XCTAssertNil(services.unlockAnnouncement, "чиста установка — нічого заднім числом")
    }

    func testDiscoveryOutsideHomeIsAnnounced() {
        services.record(.xpGuideOpened)
        XCTAssertEqual(services.unlockAnnouncement?.message, "🥚 Пасхалка: Вивести на чисту воду")
        services.dismissUnlockAnnouncement()

        services.record(.xpGuideOpened)
        XCTAssertNil(services.unlockAnnouncement, "повтор нічого не відкриває")
    }

    func testFiveThemeChangesInAMinuteFindTheDisco() {
        let settings = SettingsModel(services: services)
        for index in 0..<5 { settings.setThemeMode(index % 2 == 0 ? .dark : .light) }
        XCTAssertEqual(services.unlockAnnouncement?.message, "🥚 Пасхалка: Дискотека")
    }

    /// Скільки екранів — стільки й ціль «Як риба у воді»; кожен рахується раз.
    func testEveryScreenCountsOnceForTheFish() {
        XCTAssertEqual(Double(AppScreen.allCases.count), AchievementCatalog.definition("egg.fish")?.target)
        for screen in AppScreen.allCases.dropLast() {
            services.record(.screenOpened(screen))
            services.record(.screenOpened(screen))
        }
        XCTAssertNil(services.unlockAnnouncement)
        services.record(.screenOpened(AppScreen.allCases.last!))
        XCTAssertEqual(services.unlockAnnouncement?.message, "🥚 Пасхалка: Як риба у воді")
    }

    /// Прийнятий графік — свій тост, а «Свій ритм» — наступним, не поверх нього.
    func testAcceptedScheduleQueuesTheSecretAfterItsToast() {
        let home = HomeViewModel(services: services)
        home.openSchedule(ScheduleSuggestionDemo.wakeEarly.suggestion(for: services.profile.weekSchedule))
        home.acceptSchedule()
        XCTAssertFalse(home.toast?.message.contains("Досягнення") ?? true, "спершу — новий графік")
        home.dismissToast()
        XCTAssertEqual(home.toast?.message, "🏅 Досягнення: Свій ритм")
    }

    /// «Друга думка» — після тоста зі «Скасувати»: повернути порцію важливіше.
    func testRemovalQueuesSecondThoughtAfterUndoToast() {
        let home = HomeViewModel(services: services)
        home.add(200)
        home.add(250)
        home.dismissToast()
        let id = home.history.first { $0.amountMl == 250 }!.id
        home.remove(id: id)
        XCTAssertEqual(home.toast?.action, .restoreIntake(id))
        home.dismissToast()
        XCTAssertEqual(home.toast?.message, "🏅 Досягнення: Друга думка")
    }

    func testFinishedWeekReportIsAnnouncedAfterClosing() {
        let calendar = services.calendar
        let report = ReportViewModel(
            services: services, periods: [calendar.period(.week, containing: calendar.dayKey(offsetDays: -7, from: calendar.today))]
        )
        report.slideIndex = report.slides.count - 1
        XCTAssertNil(services.unlockAnnouncement, "поверх історії тост ліг би на «Готово»")
        report.announceUnlocks()
        XCTAssertEqual(services.unlockAnnouncement?.message, "🏅 Досягнення: Історія тижня")
    }

    func testOnlyAPastDayCountsForLookingBack() {
        let stats = StatsViewModel(services: services)
        stats.select(day: services.calendar.today)
        XCTAssertNil(services.unlockAnnouncement)
        stats.select(day: services.calendar.dayKey(offsetDays: -3, from: services.calendar.today))
        XCTAssertEqual(services.unlockAnnouncement?.message, "🏅 Досягнення: Погляд у минуле")
    }
}
