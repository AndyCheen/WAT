import XCTest
import SwiftData
import Core
import Persistence
import Notifications
@testable import Features

/// Свої кнопки порцій і шторка «Інше» з останнім об'ємом (WAT-45).
@MainActor
final class PortionButtonsFeatureTests: XCTestCase {
    private var services: AppServices!

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

    func testCustomSheetOpensWithLastConfirmedAmount() {
        let model = HomeViewModel(services: services)
        model.openCustom()
        XCTAssertEqual(model.customAmount, 300, "уперше — як до WAT-45")

        model.stepCustom(150)
        model.confirmCustom()
        model.customAmount = 100                     // будь-що між відкриттями
        model.openCustom()
        XCTAssertEqual(model.customAmount, 450)
        XCTAssertEqual(HomeViewModel(services: services).customAmount, 300, "у нової моделі — до відкриття")
    }

    /// Тап по сповіщенню відкриває шторку з типовою порцією P — текст сповіщення називає саме її.
    func testNotificationIntentKeepsTypicalPortion() {
        services.hydration.rememberCustomAmount(450)
        let model = HomeViewModel(services: services)
        model.apply(.customAmount(250))
        XCTAssertEqual(model.customAmount, 250)
    }

    func testEditedButtonsReachHomeAndSheet() {
        let editor = PortionButtonsModel(services: services)
        editor.step(.home, at: 0, up: true)
        editor.step(.customSheet, at: 3, up: true)
        XCTAssertEqual(editor.homeAmounts, [250, 500, 1000])
        XCTAssertFalse(editor.isDefault(.home))

        let home = HomeViewModel(services: services)
        XCTAssertEqual(home.quickAmounts, [250, 500, 1000])
        XCTAssertEqual(home.customChips, [150, 250, 350, 550])
        XCTAssertEqual(SettingsModel(services: services).quickAmountsSummary, "250 мл · 0.5 л · 1 л")

        editor.reset(.home)
        XCTAssertTrue(editor.isDefault(.home))
        XCTAssertFalse(editor.isDefault(.customSheet), "скидання одного місця не чіпає інше")
    }

    func testLabelsMatchTheButtons() {
        XCTAssertEqual(PortionButtonsModel.label(500, place: .home), "0.5 л")
        XCTAssertEqual(PortionButtonsModel.label(500, place: .customSheet), "500 мл")
    }
}
