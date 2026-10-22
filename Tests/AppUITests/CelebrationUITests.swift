import XCTest

/// Вікно відкриття досягнень «Хвиля» (WAT-60, SPEC-ACHIEVEMENTS §8). Годинник закріплено: на справжньому порція
/// могла б припасти на повню чи 11:11 і відкрити ще й таємне.
final class CelebrationUITests: XCTestCase {

    private static let morning = ["--uitest-now", "2026-10-01T09:00:00+03:00"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Перша порція — «Перша крапля» на весь екран: вікно справді видно, а не лише в дереві.
    func testFirstIntakeOpensTheWindow() {
        let app = launch(["--uitest-empty"] + Self.morning)
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        app.buttons["home.add.200"].tap()

        let title = app.staticTexts["celebration.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.hasPrefix("Нове досягнення: Перша крапля."), title.label)
        XCTAssertTrue(title.isHittable, "назва на екрані, а не за ним")
        let primary = app.buttons["celebration.primary"]
        XCTAssertTrue(primary.isHittable)
        XCTAssertEqual(primary.label, "Чудово")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(title.frame) && window.contains(primary.frame), "у межах вікна")
        XCTAssertFalse(app.buttons["celebration.later"].exists, "без рівня з вибором «Пізніше» немає")
        XCTAssertFalse(app.descendants(matching: .any)["celebration.page.0"].exists, "одна сторінка — без крапок")
    }

    /// «Чудово» закриває вікно, і крапки «нове» на краплі рівня за відсвятковане немає (§13 п. 14).
    func testGreatClosesAndLeavesNoNewDot() {
        let app = launch(["--uitest-empty"] + Self.morning)
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        app.buttons["home.add.200"].tap()

        let primary = app.buttons["celebration.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        // Перші 0,5 с кнопка не реагує — другий тап по кнопці порції не має змести вікно (§8.3).
        let live = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: primary)
        wait(for: [live], timeout: 5)
        Thread.sleep(forTimeInterval: 0.6)
        primary.tap()
        XCTAssertTrue(primary.waitForNonExistence(timeout: 3), "закриває перший же тап")

        let level = app.buttons["home.level"]
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertNotEqual(level.value as? String, "є нове")
        XCTAssertEqual(app.staticTexts["home.percent"].label, "10%", "головний на місці")
    }

    /// Норма, що піднімає рівень 2, — одне свято: «Ціль дня» і рядок рівня, а не окремий тост (§8.1).
    func testGoalWithLevelTwoIsOneWindowWithLevelRow() {
        let app = launch(["--uitest-empty"] + Self.morning)
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        for _ in 0..<3 {
            app.buttons["home.add.500"].tap()
            dismissCelebrationIfPresent(app, timeout: 2)
        }
        app.buttons["home.add.500"].tap()

        let title = app.staticTexts["celebration.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Ціль дня"), title.label)
        let level = app.descendants(matching: .any)["celebration.level"]
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertTrue(level.label.hasPrefix("Рівень 2"), level.label)
        XCTAssertTrue(level.label.contains("у призах"), "підпис вузла — ті самі тексти, що в тості рівня: \(level.label)")
        dismissCelebrationIfPresent(app)
        XCTAssertFalse(app.staticTexts["toast.message"].waitForExistence(timeout: 2), "тоста рівня поруч немає")
    }

    /// Порція з віджета, поки застосунку немає на екрані, — вікно «Поки тебе не було» на відкритті (§8.5).
    func testWidgetPortionIsCelebratedOnOpen() {
        let app = launch(["--uitest-empty", "--widget-action", "add:250"] + Self.morning)
        let title = app.staticTexts["celebration.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(title.label.hasPrefix("Поки тебе не було: Перша крапля."), title.label)
        XCTAssertTrue(title.isHittable)

        // «Перша крапля» й «На робочому столі» — дві сторінки з крапками.
        XCTAssertTrue(app.descendants(matching: .any)["celebration.page.1"].exists)
        XCTAssertEqual(app.buttons["celebration.primary"].label, "Далі")
        let titles = dismissCelebrationIfPresent(app)
        XCTAssertEqual(titles.count, 2, "\(titles)")
        XCTAssertTrue(titles.last?.contains("На робочому столі") ?? false, "\(titles)")
        XCTAssertTrue(app.staticTexts["250 мл"].waitForExistence(timeout: 5), "порція в історії")
    }
}
