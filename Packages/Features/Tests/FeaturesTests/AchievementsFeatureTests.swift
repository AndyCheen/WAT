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

    // MARK: - Вікно відкриття (§8)

    /// Назви сторінок вікна, що зараз на екрані.
    private var shownTitles: [String] { services.celebration?.pages.map(\.title) ?? [] }

    func testFirstIntakeOpensTheWindowInsteadOfAToast() {
        let model = HomeViewModel(services: services)
        model.add(200)

        XCTAssertEqual(shownTitles, ["Перша крапля"])
        XCTAssertEqual(services.celebration?.context, .action)
        XCTAssertEqual(services.celebration?.pages.first?.label, "Нове досягнення")
        XCTAssertEqual(services.celebration?.finishTitle, "Чудово")
        XCTAssertNil(model.toast, "досягнення — вікно, а не тост")
        XCTAssertEqual(model.pulse?.kind, .celebration, "вібрує саме вікно, у мить появи")

        services.dismissCelebration()
        model.celebrationDidClose()
        XCTAssertNil(services.celebration)
        XCTAssertFalse(model.hasNewAchievements, "після «Чудово» крапки «нове» за відсвятковане немає (§13 п. 14)")
    }

    func testSeveralUnlocksInOneActionArePagesOfOneWindow() {
        let model = HomeViewModel(services: services)
        services.gamification.xp.rules = services.gamification.xp.rules
            .applyingBalance([XPRules.BalanceKey.xpMultiplier: "0.1"])

        model.add(1000) // «Перша крапля» й «Великий ковток»: решта з WAT-60 — не з першого дня

        XCTAssertEqual(shownTitles, ["Перша крапля", "Великий ковток"])
        XCTAssertNil(model.toast)
    }

    func testIntakeWithoutUnlockGivesNoWindowAndNoToast() {
        let model = HomeViewModel(services: services)
        model.add(200)
        services.dismissCelebration()

        model.add(200)
        XCTAssertNil(services.celebration)
        XCTAssertNil(model.toast)
    }

    // MARK: - Екран 2e (§5, §7.4)

    func testCounterIsGlobalAndFiltersCombine() {
        services.hydration.addIntake(amountMl: 600) // «Перша крапля» відкрита, «Великий ковток» у процесі
        let model = AchievementsViewModel(services: services)

        XCTAssertEqual(model.unlockedCount, 1)
        XCTAssertEqual(model.totalCount, 101, "111 чинних без 10 пасхалок (SPEC-ACHIEVEMENTS-CATALOG §10.4)")

        model.selectState(.inProgress)
        XCTAssertTrue(model.filtered.contains { $0.key == "big.gulp" })
        XCTAssertTrue(model.filtered.allSatisfy { $0.state == .inProgress })
        XCTAssertEqual(model.unlockedCount, 1, "чип стану не змінює лічильник")

        model.selectCategory(.streak)
        XCTAssertEqual(model.emptyState, .filtered)

        model.resetFilters()
        XCTAssertNil(model.category)
        XCTAssertEqual(model.stateFilter, .all)
        XCTAssertEqual(model.filtered.count, 101)
    }

    func testCategoryFilterCoversWaterAchievements() {
        let model = AchievementsViewModel(services: services)
        model.selectCategory(.water)
        XCTAssertEqual(model.filtered.count, 12, "§4.1 без «Глечика» й «Розминки» (WAT-60)")
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

    /// Пасхалка — своя сторінка вікна, окремий лічильник «🥚 N», рядок у картці першої.
    func testEggHasItsOwnPageAndCounter() {
        let home = HomeViewModel(services: services)
        home.customAmount = 300
        home.confirmCustom()
        XCTAssertEqual(shownTitles, ["Перша крапля", "Своя мірка"])
        services.dismissCelebration()

        home.customAmount = 314
        home.confirmCustom()
        let egg = services.celebration?.pages.first
        XCTAssertEqual(egg?.title, "Пі")
        XCTAssertEqual(egg?.label, "Пасхалка")
        XCTAssertEqual(egg?.reveal, .egg)
        XCTAssertEqual(egg?.note, "Пасхалка! Тут їх більше", "перша — «Тут їх більше» замість «Далі»")
        XCTAssertNil(egg?.next)
        services.dismissCelebration()

        let screen = AchievementsViewModel(services: services)
        screen.reload()
        XCTAssertEqual(screen.totalCount, 101, "знайдена пасхалка видимий каталог не роздуває")
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

    /// Ціль в одну дію — ні смуги, ні «0/1» (WAT-51): досягнення або є, або ні. Багатокрокові — як і були.
    func testOneStepAchievementShowsNoProgress() {
        let model = AchievementsViewModel(services: services)
        let once = model.items.first { $0.key == "first.drop" }!
        XCTAssertTrue(once.isOneStep)
        XCTAssertFalse(once.showsProgress)
        XCTAssertEqual(once.tileStatus, .locked)
        XCTAssertEqual(once.detailStatus, .locked, "у картці лишається лише рядок нагороди")
        XCTAssertEqual(once.progressAccessibilityValue, "Ще не відкрито")
        XCTAssertEqual(once.detailAccessibilityValue, "\(once.details). Ще не відкрито. \(once.rewardLabel)")

        let ladder = model.items.first { $0.key == "volume.10l" }!
        XCTAssertFalse(ladder.isOneStep)
        XCTAssertEqual(ladder.tileStatus, .progress(fraction: 0, label: ladder.progressLabel, unit: ladder.unitLabel))

        services.hydration.addIntake(amountMl: 200)
        model.reload()
        XCTAssertEqual(model.items.first { $0.key == "first.drop" }?.tileStatus, .unlocked)
    }

    /// Об'єм — у літрах, як на кнопках порцій (WAT-52): плитка «0.2/20 л», картка «0.2 / 20 л», VoiceOver словами.
    func testVolumeLadderShowsLitresOnTileCardAndVoiceOver() {
        services.hydration.addIntake(amountMl: 250)
        let model = AchievementsViewModel(services: services)

        let bucket = model.items.first { $0.key == "volume.10l" }!
        XCTAssertEqual(bucket.tileStatus, .progress(fraction: 0.0125, label: "0.2/20", unit: "л"))
        XCTAssertEqual(bucket.detailStatus, .progress(fraction: 0.0125, label: "0.2 / 20", unit: "л"))
        XCTAssertEqual(bucket.progressAccessibilityValue, "Прогрес 0,2 із 20 літрів")
        XCTAssertEqual(bucket.detailAccessibilityValue, "20 л води загалом. Прогрес 0,2 із 20 літрів. \(bucket.rewardLabel)")

        let gulp = model.items.first { $0.key == "big.gulp" }!
        XCTAssertEqual(gulp.tileStatus, .progress(fraction: 0.25, label: "250/1000", unit: "мл"), "ціль до 1 л — мл")
        XCTAssertEqual(gulp.progressAccessibilityValue, "Прогрес 250 із 1000 мілілітрів")

        let portions = model.items.first { $0.key == "portions.100" }!
        XCTAssertEqual(portions.tileStatus, .progress(fraction: 0.01, label: "1/100"), "штуки — без одиниці")
        XCTAssertEqual(portions.progressAccessibilityValue, "Прогрес 1 із 100")
    }

    func testDisabledFeatureShowsCaptionInsteadOfProgress() {
        services.profile.dayRhythmEnabled = false
        let model = AchievementsViewModel(services: services)
        XCTAssertEqual(model.items.first { $0.key == "rhythm.morning" }?.tileStatus,
                       .caption("Увімкни «Ритм дня» в налаштуваннях"))
    }

    // MARK: - Вікно поза головним

    /// Після оновлення досягнення відкриваються з історії — одне вікно «Поки тебе не було» на всі (§8.5).
    func testUpdateBackfillsFromHistoryWithOneWindow() {
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
        let window = updated.celebration
        XCTAssertEqual(window?.context, .whileAway)
        XCTAssertEqual(window?.pages.count, 1, "більше трьох — одна сторінка сіткою")
        XCTAssertTrue(window?.pages.first?.title.hasPrefix("Нові досягнення:") ?? false, window?.pages.first?.title ?? "вікна немає")
        XCTAssertEqual(window?.pages.first?.label, "Поки тебе не було")
        XCTAssertNil(services.celebration, "чиста установка — нічого заднім числом")
    }

    /// Відкрите до версії з вікном — відсвятковане: оновлення не вивалює вікно за минуле (§8.5).
    func testUnlockedBeforeTheUpdateIsAlreadyCelebrated() {
        services.hydration.addIntake(amountMl: 200)
        services.settleCelebrations()
        services.profile.celebrationsSince = nil
        services.bootstrap()
        XCTAssertNil(services.celebration)
        XCTAssertFalse(services.hasPendingCelebrations)
    }

    func testDiscoveryOutsideHomeIsCelebrated() {
        services.record(.xpGuideOpened)
        XCTAssertEqual(shownTitles, ["Вивести на чисту воду"])
        XCTAssertEqual(services.celebration?.pages.first?.label, "Пасхалка")
        services.dismissCelebration()

        services.record(.xpGuideOpened)
        XCTAssertNil(services.celebration, "повтор нічого не відкриває")
    }

    /// «Темна сторона» — вікном поверх налаштувань, а не після повернення на головний.
    func testDarkThemeInSettingsCelebratesOverSettings() {
        let settings = SettingsModel(services: services)
        settings.setThemeMode(.dark)
        XCTAssertEqual(shownTitles, ["Темна сторона"])
    }

    func testFiveThemeChangesInAMinuteFindTheDisco() {
        let settings = SettingsModel(services: services)
        var celebrated: [String] = []
        for index in 0..<5 {
            settings.setThemeMode(index % 2 == 0 ? .dark : .light)
            // Вікно людина закриває, перш ніж перемикати далі.
            celebrated += shownTitles
            services.dismissCelebration()
        }
        XCTAssertEqual(celebrated, ["Темна сторона", "Дискотека"])
    }

    /// Скільки екранів — стільки й ціль «Як риба у воді»; кожен рахується раз.
    func testEveryScreenCountsOnceForTheFish() {
        XCTAssertEqual(Double(AppScreen.allCases.count), AchievementCatalog.definition("egg.fish")?.target)
        for screen in AppScreen.allCases.dropLast() {
            services.record(.screenOpened(screen))
            services.record(.screenOpened(screen))
        }
        XCTAssertNil(services.celebration)
        services.record(.screenOpened(AppScreen.allCases.last!))
        XCTAssertEqual(shownTitles, ["Як риба у воді"])
    }

    /// Прийнятий графік — свій тост, а «Свій ритм» — вікном після нього, не поверх.
    func testAcceptedScheduleCelebratesTheSecretAfterItsToast() {
        let home = HomeViewModel(services: services)
        home.openSchedule(ScheduleSuggestionDemo.wakeEarly.suggestion(for: services.profile.weekSchedule))
        home.acceptSchedule()
        XCTAssertNotNil(home.toast, "спершу — новий графік")
        XCTAssertNil(services.celebration, "вікно чекає тоста")
        home.dismissToast()
        XCTAssertEqual(shownTitles, ["Свій ритм"])
        XCTAssertEqual(services.celebration?.pages.first?.label, "Таємне досягнення")
        XCTAssertEqual(services.celebration?.pages.first?.reveal, .secret)
    }

    /// «Нерішучість» — вікном після тоста зі «Скасувати»: повернути порцію важливіше.
    func testRemovalCelebratesIndecisionAfterUndoToast() {
        let home = HomeViewModel(services: services)
        home.add(200)
        services.dismissCelebration()
        for attempt in 1...3 {
            home.add(250)
            home.dismissToast()
            let id = home.history.first { $0.amountMl == 250 }!.id
            home.remove(id: id)
            XCTAssertEqual(home.toast?.action, .restoreIntake(id))
            XCTAssertNil(services.celebration, "поверх «Скасувати» вікна немає")
            home.dismissToast()
            if attempt < 3 { XCTAssertNil(services.celebration, "«Друга думка» знято (WAT-60) — за одне скасування нічого") }
        }
        XCTAssertEqual(shownTitles, ["Нерішучість"])
    }

    /// Відкрите на останньому слайді звіту — вікном після закриття, не поверх «Готово».
    func testFinishedWeekReportIsCelebratedAfterClosing() {
        let calendar = services.calendar
        let report = ReportViewModel(
            services: services, periods: [calendar.period(.week, containing: calendar.dayKey(offsetDays: -7, from: calendar.today))]
        )
        report.appeared()
        report.slideIndex = report.slides.count - 1
        XCTAssertNil(services.celebration, "поверх історії вікно лягло б на «Готово»")
        report.disappeared()
        XCTAssertEqual(shownTitles, ["Історія тижня"])
    }

    func testOnlyAPastDayCountsForLookingBack() {
        let stats = StatsViewModel(services: services)
        stats.select(day: services.calendar.today)
        XCTAssertNil(services.celebration)
        stats.select(day: services.calendar.dayKey(offsetDays: -3, from: services.calendar.today))
        XCTAssertEqual(shownTitles, ["Погляд у минуле"])
    }
}
