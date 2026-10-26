import XCTest

/// Режим розробника (WAT-68): вхід із «Налаштувань», приз однією кнопкою, порція в минулий день о вибраній хвилині.
final class DeveloperUITests: XCTestCase {

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

    /// Рядок унизу «Налаштувань»: гортати, поки він не стане досяжним.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }

    func testSettingsOpensDeveloperModeAndGrantsPrize() {
        let app = launch(["--uitest-empty", "--start-screen", "settings"])
        let entry = app.buttons["settings.developer"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        scrollTo(entry, in: app)
        entry.tap()

        let freeze = app.buttons["developer.prize.streak.freeze"]
        XCTAssertTrue(freeze.waitForExistence(timeout: 5))
        scrollTo(freeze, in: app)
        freeze.tap()

        XCTAssertTrue(app.staticTexts["Готових: 1"].waitForExistence(timeout: 5), "заморозка лягла в інвентар")
    }

    /// Годинник стоїть на 15:00 1 жовтня: порція «учора о 15:00» лягає в 30 вересня, а сьогоднішній день порожній.
    func testPastDayIntakeAtChosenTime() {
        let app = launch(["--uitest-empty", "--uitest-now", "2026-10-01T15:00:00+03:00",
                          "--start-screen", "developer:day"])
        let yesterday = app.buttons["developer.day.yesterday"]
        XCTAssertTrue(yesterday.waitForExistence(timeout: 15))
        yesterday.tap()
        XCTAssertTrue(app.staticTexts["Ср, 30 вересня"].waitForExistence(timeout: 5))

        app.buttons["developer.day.amount.500"].tap()
        let add = app.buttons["developer.day.add"]
        scrollTo(add, in: app)
        add.tap()
        // Відкрите порцією з минулого дня — відкрите заднім числом: вікна немає, але й не заважає, якщо буде.
        dismissCelebrationIfPresent(app, timeout: 1)

        XCTAssertTrue(app.staticTexts["15:00 · 500 мл"].waitForExistence(timeout: 5))
        let volume = app.staticTexts["developer.day.volume"]
        XCTAssertTrue(volume.exists)
        XCTAssertEqual(volume.label, "500 / 2000 мл · 25 %")
    }
}
