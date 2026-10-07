import XCTest
import SwiftData
import Core
import Persistence
import DesignSystem
import Gamification
@testable import Features

/// Вікно «Шлях рівнів» на рівні моделей і текстів (SPEC-PRIZES §16). Годинник — 18.07.2026, 10:00.
@MainActor
final class LevelRoadFeatureTests: XCTestCase {
    private var services: AppServices!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18; c.hour = 10
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        services = AppServices(container: Database.makeInMemoryContainer(), clock: FixedClock(now: cal.date(from: c)!))
        services.bootstrap()
        defaults = UserDefaults(suiteName: "LevelRoadFeatureTests")
        defaults.removePersistentDomain(forName: "LevelRoadFeatureTests")
    }

    private func reachLevel(_ level: Int) {
        let game = services.gamification
        let need = LevelCalculator.totalXpRequired(forLevel: level, curve: game.xp.curve) - game.levelProgress().totalXp
        game.xp.award(amount: need, reason: .questCompleted, refId: UUID(), at: services.calendar.now)
        game.grantLevelRewards(at: services.calendar.now)
    }

    // MARK: - Тексти (§16.8)

    func testPossibleOutcomesText() {
        XCTAssertEqual(LevelRoadPresenter.possibleText(.regular), "Може випасти: ⚡ 🧊 🌟")
        XCTAssertEqual(LevelRoadPresenter.possibleText(.grand), "Може випасти: 🌟 ⚡×2 🧊×2",
                       "у великому — лише набори й 🌟")
    }

    func testChoiceAheadNamesBothPrizes() {
        let ahead = LevelRoadPresenter.upcoming(.choice([.freeze, .boost]))
        XCTAssertEqual(ahead.icon, .pair(["🧊", "⚡"]))
        XCTAssertEqual(ahead.title, "Приз на вибір")
        XCTAssertEqual(ahead.subtitle, "Заморозка серії або подвійний XP")
    }

    func testChoiceSubtitleFollowsSelection() {
        XCTAssertEqual(LevelRoadPresenter.choiceSubtitle(selected: nil, done: false), "Можна взяти один із двох")
        XCTAssertEqual(LevelRoadPresenter.choiceSubtitle(selected: RewardCatalog.freezeKey, done: false),
                       "Пропущений день не обірве серію")
        XCTAssertEqual(LevelRoadPresenter.choiceSubtitle(selected: RewardCatalog.freezeKey, done: true),
                       "✓ 🧊 у твоїх призах")
    }

    func testRevealOutcomeTexts() {
        let single = LevelRoadPresenter.revealOutcome([.boost])
        XCTAssertEqual(single.subtitle, "Уже у твоїх призах")
        XCTAssertEqual(single.count, 1)

        let bundle = LevelRoadPresenter.revealOutcome([RewardGrant(RewardCatalog.freezeKey, count: 2)])
        XCTAssertEqual(bundle.title, "Заморозка серії")
        XCTAssertEqual(bundle.subtitle, "2 шт. — уже у твоїх призах")
        XCTAssertEqual(bundle.count, 2, "кількість — бейджем, а не в назві (SPEC-PRIZES §8.1)")

        let combo = LevelRoadPresenter.revealOutcome([.freeze, .boost])
        XCTAssertEqual(combo.emojis, ["🧊", "⚡"])
        XCTAssertEqual(combo.subtitle, "Обидва — уже у твоїх призах")
    }

    func testRowsMarkCurrentAndFog() {
        reachLevel(9)
        let rows = LevelRoadPresenter.rows(services.gamification.levelRoad())
        let current = rows.first { $0.isCurrent }!
        XCTAssertEqual(current.level, 9)
        XCTAssertEqual(rows.first?.content, .start("Старт"))
        XCTAssertEqual(rows.first { $0.level == 13 }?.style, .fogged)
        if case .card(_, let title, _, let tone, _) = rows.first(where: { $0.level == 13 })!.content {
            XCTAssertEqual(title, "Ще не видно")
            XCTAssertEqual(tone, .fogged)
        } else {
            XCTFail("туман — розмита картка")
        }
    }

    // MARK: - Довідник «Звідки XP» (§16.14)

    func testGuideFollowsBalance() {
        var rules = XPRules.default.applyingBalance([
            XPRules.BalanceKey.xpPerVolumeStep: "4", XPRules.BalanceKey.volumeStepMl: "200",
            XPRules.BalanceKey.xpMultiplier: "2"
        ])
        rules.perDailyGoal = 50
        let rows = LevelRoadPresenter.guideRows(rules: rules, dayRhythm: true)
        XCTAssertEqual(rows.first?.title, "Вода, кожні 200 мл")
        XCTAssertEqual(rows.first?.value, "+8 XP", "множник балансу — і в довіднику")
        XCTAssertEqual(rows.first { $0.title == "Норма дня" }?.value, "+100 XP")
        XCTAssertTrue(rows.contains { $0.title == "Ціль частини доби" })

        let plain = LevelRoadPresenter.guideRows(rules: .default, dayRhythm: false)
        XCTAssertFalse(plain.contains { $0.title == "Ціль частини доби" }, "без ритму дня XP за частини немає")
    }

    // MARK: - Модель вікна

    func testChoiceClaimShowsConfirmationThenCollapses() async throws {
        reachLevel(4)
        let model = LevelRoadModel(services: services, defaults: defaults)
        model.claimHold = .milliseconds(10)
        XCTAssertEqual(model.focusLevel, 4)

        model.claim(level: 4)
        XCTAssertNil(model.claimedLevel, "без вибору «Забрати» нічого не робить")

        model.select(level: 4, key: RewardCatalog.boostKey)
        model.claim(level: 4)
        XCTAssertEqual(model.claimedLevel, 4)
        XCTAssertEqual(services.gamification.prizeInventory().ready.first { $0.key == RewardCatalog.boostKey }?.count, 2,
                       "⚡ з 2-го рівня + обраний")

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertNil(model.claimedLevel)
        XCTAssertEqual(model.road.nodes.first { $0.level == 4 }?.status, .claimed)
    }

    func testMysteryOpensRevealAndReloadsAfter() {
        reachLevel(6)
        let model = LevelRoadModel(services: services, defaults: defaults)
        model.open(level: 6)

        XCTAssertEqual(model.reveal?.level, 6)
        XCTAssertEqual(model.reveal?.kicker, "Таємний приз · рівень 6")
        model.open(level: 6)
        XCTAssertEqual(model.reveal?.level, 6, "друге відкриття під час розкриття ігнорується")

        model.finishReveal()
        XCTAssertNil(model.reveal)
        XCTAssertEqual(model.road.nodes.first { $0.level == 6 }?.claimKind, .mystery)
    }

    /// Позначка повтору прогресу оновлюється щоразу, а перше відкриття нічого не анімує (§16.15).
    func testReplayRemembersSeenXp() {
        reachLevel(3)
        let model = LevelRoadModel(services: services, defaults: defaults)
        model.replayProgress(reduceMotion: false)
        XCTAssertEqual(defaults.integer(forKey: LevelRoadModel.seenTotalXpKey), services.gamification.levelProgress().totalXp)
        XCTAssertEqual(model.railPosition, LevelRoadModel.position(of: services.gamification.levelProgress()))
    }

    // MARK: - 3f і тост

    func testProgressShowsPendingCallAndOpensWindow() {
        reachLevel(4)
        let progress = ProgressViewModel(services: services)
        XCTAssertEqual(progress.pendingReward?.level, 4)

        progress.openLevelRoad()
        XCTAssertTrue(progress.showLevelRoad)
        XCTAssertNotNil(progress.levelRoad)

        progress.levelRoad?.select(level: 4, key: RewardCatalog.freezeKey)
        progress.levelRoad?.claim(level: 4)
        progress.closeLevelRoad()
        XCTAssertNil(progress.pendingReward, "після вибору заклик зникає")
        XCTAssertEqual(progress.road.nextReward?.level, 6)
    }

    func testLevelToastDependsOnReward() {
        XCTAssertEqual(HomeViewModel.levelRewardToast(4)?.message, "Рівень 4! Обери приз: 🧊 або ⚡")
        XCTAssertEqual(HomeViewModel.levelRewardToast(4)?.action, .showLevelRoad)
        XCTAssertEqual(HomeViewModel.levelRewardToast(6)?.message, "Рівень 6! 🎁 Чекає таємний приз")
        XCTAssertEqual(HomeViewModel.levelRewardToast(8)?.message, "Рівень 8! 🧊 Заморозка серії — у призах")
        XCTAssertEqual(HomeViewModel.levelRewardToast(8)?.action, .showPrize(RewardCatalog.freezeKey))
        XCTAssertNil(HomeViewModel.levelRewardToast(5), "рівень без призу — звичайний тост «Рівень 5!»")
    }

    // MARK: - Звіт місяця (§16.16)

    func testMonthReportCountsPrizes() {
        services.gamification.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        let calendar = services.calendar
        // Звіт без води — порожній слайд; порція потрібна, щоб з'явився слайд «Гра».
        services.hydration.addIntake(amountMl: 500)

        func gameBadges(_ period: ReportPeriod) -> [String]? {
            let presenter = ReportPresenter(
                report: services.insights.report(for: period),
                game: services.gamification.periodSummary(days: calendar.days(in: period)),
                streak: services.gamification.streakSummary(),
                recentGoalDays: Array(repeating: false, count: 7),
                schedule: services.profile.schedule(isWeekend: false),
                weekendScheduleEnabled: false, dayPartXp: 10, today: calendar.today,
                tomorrowMorning: "08:00", nowMinute: nil, calendar: calendar
            )
            for slide in presenter.slides {
                if case .game(_, _, _, let badges, _) = slide { return badges }
            }
            return nil
        }

        XCTAssertEqual(gameBadges(calendar.period(.month, containing: calendar.today))?.contains("🎁 2 призи"), true)
        XCTAssertFalse(gameBadges(calendar.period(.week, containing: calendar.today))?.contains { $0.hasPrefix("🎁") } ?? false,
                       "у тижневому звіті призів не рахуємо")
    }
}
