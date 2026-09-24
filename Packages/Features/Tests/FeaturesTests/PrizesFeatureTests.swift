import XCTest
import SwiftData
import Core
import Persistence
import Hydration
import Gamification
@testable import Features

/// Модуль «Призи» на рівні моделей екранів: тексти картки й рядків (SPEC-PRIZES §4.1, §8.2),
/// дія з картки, крапка «нове».
@MainActor
final class PrizesFeatureTests: XCTestCase {
    private var services: AppServices!
    private var clock: FixedClock!

    private static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = day; c.hour = hour; c.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    override func setUp() async throws {
        try await super.setUp()
        clock = FixedClock(now: Self.date(day: 18, hour: 20, minute: 40))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock)
        services.bootstrap()
    }

    private func closeDay(_ day: Int) {
        for hour in [9, 12, 15, 18] {
            services.hydration.addIntake(amountMl: 500, at: Self.date(day: day, hour: hour))
        }
    }

    private func stack(_ model: PrizeInventoryModel, _ key: String) -> PrizeStack {
        model.inventory.ready.first { $0.key == key }!
    }

    // MARK: - Заморозка

    func testFreezeCardNamesYesterdayAndTheStreakItSaves() {
        for day in 14...16 { closeDay(day) }
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        let model = PrizeInventoryModel(services: services)
        let freeze = stack(model, RewardCatalog.freezeKey)

        XCTAssertEqual(model.presenter.rowSubtitle(freeze).text, "Можна врятувати серію 3 дні")
        XCTAssertTrue(model.presenter.rowSubtitle(freeze).isWarning)

        let card = model.presenter.detail(for: .stack(freeze), inventory: model.inventory, at: model.now)
        XCTAssertEqual(card.action?.title, "Заморозити вчора")
        XCTAssertEqual(card.status, .warning("Серія 3 дні збережеться"))
        XCTAssertGreaterThanOrEqual(card.count, 2, "кількість — бейдж на іконці, а не частина назви")
        XCTAssertEqual(card.title, "Заморозка серії")
    }

    func testUsingFreezeClosesCardAndNextOneTargetsToday() {
        closeDay(16)
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        let model = PrizeInventoryModel(services: services)
        let before = stack(model, RewardCatalog.freezeKey).count

        model.select(.stack(stack(model, RewardCatalog.freezeKey)))
        model.performSelectedAction()

        XCTAssertNil(model.selected, "після дії картка закривається")
        XCTAssertEqual(model.feedback?.feedback, .goalReached)
        let after = stack(model, RewardCatalog.freezeKey)
        XCTAssertEqual(after.count, before - 1, "стос зменшився")
        let card = model.presenter.detail(for: .stack(after), inventory: model.inventory, at: model.now)
        XCTAssertEqual(card.action?.title, "Заморозити сьогодні")
        XCTAssertEqual(card.status, .note("Якщо все ж закриєш норму — заморозка повернеться"))
    }

    func testFreezeIsDisabledWhenTodayIsAlreadyCounted() {
        closeDay(17)
        closeDay(18)
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        let model = PrizeInventoryModel(services: services)
        let freeze = stack(model, RewardCatalog.freezeKey)

        let card = model.presenter.detail(for: .stack(freeze), inventory: model.inventory, at: model.now)
        XCTAssertEqual(card.action?.title, "Сьогодні вже зараховано")
        XCTAssertEqual(card.action?.isEnabled, false)
        XCTAssertNotNil(card.action?.disabledHint, "VoiceOver пояснює, чому кнопка неактивна")
    }

    // MARK: - Буст

    func testBoostButtonTellsHowLongItWillLast() {
        services.gamification.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        let model = PrizeInventoryModel(services: services)
        let boost = stack(model, RewardCatalog.boostKey)

        let card = model.presenter.detail(for: .stack(boost), inventory: model.inventory, at: model.now)
        XCTAssertEqual(card.action?.title, "Увімкнути на 3 год 20 хв")
        XCTAssertEqual(model.presenter.rowSubtitle(boost).text, "×2 XP до кінця дня")
    }

    func testActiveBoostShowsTimerWithoutButtonAndBlocksAnother() {
        services.gamification.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        services.gamification.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        let model = PrizeInventoryModel(services: services)
        model.select(.stack(stack(model, RewardCatalog.boostKey)))
        model.performSelectedAction()

        XCTAssertEqual(model.feedback?.feedback, .toggle)
        let active = model.inventory.active.first!
        let running = model.presenter.detail(for: .active(active), inventory: model.inventory, at: model.now)
        XCTAssertNil(running.action, "у діючого призу кнопки немає")
        XCTAssertEqual(running.status, .timer("3:20"))
        XCTAssertEqual(running.details, "Діє до 00:00")
        XCTAssertTrue(running.accessibilityValue.contains("3 години 20 хвилин"), "VoiceOver не читає «3:20» як час")
        XCTAssertEqual(model.presenter.activeSubtitle(active), "×2 XP · діє до 00:00")

        let other = model.presenter.detail(
            for: .stack(stack(model, RewardCatalog.boostKey)), inventory: model.inventory, at: model.now
        )
        XCTAssertEqual(other.action?.isEnabled, false)
        XCTAssertEqual(other.status, .info("Уже діє до 00:00"))
    }

    // MARK: - «Нове»

    func testOpeningStackCardClearsItsNewDot() {
        services.gamification.grantPrize(key: RewardCatalog.freezeKey, source: .seed)
        services.gamification.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        let model = PrizeInventoryModel(services: services)
        XCTAssertTrue(model.inventory.ready.allSatisfy(\.isNew))

        model.select(.stack(stack(model, RewardCatalog.freezeKey)))
        model.select(nil)

        XCTAssertEqual(model.inventory.ready.map(\.isNew), [false, true])
    }

    func testPrizesScreenKeepsDotsForThisVisit() {
        services.gamification.grantPrize(key: RewardCatalog.boostKey, source: .seed)
        let model = PrizeInventoryModel(services: services)

        model.reloadMarkingSeen()

        XCTAssertTrue(model.inventory.ready.first!.isNew, "крапку видно весь візит")
        XCTAssertFalse(services.gamification.hasUnseenPrizes, "а наступного разу її вже немає")
    }

    // MARK: - Формат

    func testDurationsAndPlurals() {
        XCTAssertEqual(PrizePresenter.shortDuration(3 * 3600 + 20 * 60), "3:20")
        XCTAssertEqual(PrizePresenter.shortDuration(30), "0:01", "хвилини вгору — «0:00» читалось би як «скінчився»")
        XCTAssertEqual(PrizePresenter.compactDuration(10 * 60), "10 хв")
        XCTAssertEqual(PrizePresenter.compactDuration(2 * 3600), "2 год")
        XCTAssertEqual(PrizePresenter.longDuration(1 * 3600 + 1 * 60), "1 година 1 хвилина")
        XCTAssertEqual(PrizePresenter.longDuration(11 * 3600 + 22 * 60), "11 годин 22 хвилини")
        XCTAssertEqual(PrizePresenter.days(1), "1 день")
        XCTAssertEqual(PrizePresenter.days(12), "12 днів")
        XCTAssertEqual(PrizePresenter.days(22), "22 дні")
    }
}
