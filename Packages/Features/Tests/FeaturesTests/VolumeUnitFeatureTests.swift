import XCTest
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
@testable import Features

/// Системи об'єму (WAT-46): в унціях — цілі «унц.» скрізь, кроки в унціях; назад на мілілітри — як було.
@MainActor
final class VolumeUnitFeatureTests: XCTestCase {
    private var services: AppServices!
    private let oz = VolumeUnit.usFluidOunces

    override func setUp() async throws {
        try await super.setUp()
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 1; parts.hour = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        services = AppServices(container: Database.makeInMemoryContainer(),
                               clock: FixedClock(now: calendar.date(from: parts)!),
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    func testSettingsSwitchToOuncesAndBack() {
        let settings = SettingsModel(services: services)
        settings.setVolumeUnit(.usFluidOunces)
        XCTAssertEqual(settings.quickAmountsSummary, "8 · 16 · 32 унц.")
        XCTAssertEqual(settings.goalLabel, "68 унц.")
        XCTAssertEqual(settings.goalStepLabel, "Крок — 4 унц.")
        XCTAssertEqual(settings.volumeUnitExample, "8 унц. · 64 унц.")
        settings.stepGoal(up: true)
        XCTAssertEqual(settings.goalLabel, "72 унц.", "68 → найближче кратне 4 вгору")
        settings.stepGoal(up: true)
        XCTAssertEqual(settings.goalLabel, "76 унц.")

        settings.setVolumeUnit(.milliliters)
        XCTAssertEqual(settings.quickAmountsSummary, "200 мл · 500 мл · 1 л")
        XCTAssertEqual(settings.goalStepLabel, "Крок — 100 мл")
    }

    func testHomeShowsOunces() {
        SettingsModel(services: services).setVolumeUnit(.usFluidOunces)
        let home = HomeViewModel(services: services)
        home.add(home.quickAmounts[0])
        XCTAssertEqual(home.volumeLabel, "8 / 68 унц.")
        XCTAssertEqual(HomeScreen.amountTitle(home.quickAmounts[2], home.volumeUnit), "32 унц.")
        XCTAssertEqual(home.customChips.map(oz.units), [6, 8, 12, 16])

        home.openCustom()
        XCTAssertEqual(oz.units(home.customAmount), 10, "уперше — 300 мл, показано як 10 унц.")
        home.stepCustom(up: true)
        XCTAssertEqual(oz.units(home.customAmount), 11, "крок — унція")
        XCTAssertEqual(home.calibrationChoices.map(oz.units), [6, 8, 10, 12, 14])
    }

    /// Капсула частини доби: «ще N унц.» — вгору до цілої, як у чекпоінта.
    func testDayPartPillInOunces() throws {
        SettingsModel(services: services).setVolumeUnit(.usFluidOunces)
        let line = try XCTUnwrap(HomeViewModel(services: services).dayPartLine())
        guard case .pending(_, let title, _, _) = line.content else { return XCTFail("капсула має бути «ще…»") }
        XCTAssertTrue(title.hasPrefix("До 12:00 — ще "), title)
        XCTAssertTrue(title.hasSuffix(" унц."), title)
        XCTAssertTrue(line.accessibilityLabel.contains(" унц."), line.accessibilityLabel)
    }

    func testPresentersUseOunces() {
        XCTAssertEqual(ReportFormat.volume(2000, oz), "68 унц.")
        XCTAssertEqual(ReportFormat.volume(2000), "2 л", "мілілітри — як були")
        XCTAssertEqual(ReportFormat.big(52_000, oz).unit, "унц.")
        XCTAssertEqual(ReportFormat.big(52_000, oz).value, 1758)

        let rows = LevelRoadPresenter.guideRows(rules: .default, dayRhythm: true, unit: oz)
        XCTAssertEqual(rows.first?.title, "Вода, кожні 8 унц.")
    }

    func testPortionButtonsStepInOunces() {
        SettingsModel(services: services).setVolumeUnit(.usFluidOunces)
        let editor = PortionButtonsModel(services: services)
        XCTAssertTrue(editor.isDefault(.home), "типові нової системи — без «Повернути типові»")
        editor.step(.home, at: 0, up: true)
        editor.step(.home, at: 2, up: true)
        XCTAssertEqual(editor.homeAmounts.map(oz.units), [9, 16, 34], "до 32 oz — по 1, далі — по 2")
        editor.reset(.home)
        XCTAssertEqual(editor.homeAmounts.map(oz.units), [8, 16, 32])
    }
}
