import XCTest

/// E2E-сценарії з PLAN.md §9. Застосунок стартує з in-memory базою:
/// `--uitest-empty` — чиста, `--uitest-demo` — з демо-історією.
final class SmokeUITests: XCTestCase {

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

    // MARK: - Головний екран

    func testLaunchesWithEmptyState() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["home.percent"].label, "0%")
    }

    func testAddIntakeUpdatesProgressAndHistory() {
        let app = launch(["--uitest-empty"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 15))

        app.buttons["home.add.500"].tap()

        XCTAssertEqual(percent.label, "25%", "500 мл від норми 2000 мл")
        XCTAssertTrue(app.staticTexts["500 мл"].exists, "порція зʼявилась в історії")
    }

    func testUndoRemovesIntakeAndRollsBackProgress() {
        let app = launch(["--uitest-empty"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 15))

        app.buttons["home.add.500"].tap()
        XCTAssertEqual(percent.label, "25%")

        app.staticTexts["500 мл"].tap()
        app.buttons["history.delete"].firstMatch.tap()

        XCTAssertEqual(percent.label, "0%", "видалення повертає прогрес")
    }

    func testToastUndoBringsThePortionBack() {
        let app = launch(["--uitest-empty"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 15))

        app.buttons["home.add.500"].tap()
        app.staticTexts["500 мл"].tap()
        app.buttons["history.delete"].firstMatch.tap()
        XCTAssertEqual(percent.label, "0%")

        let undo = app.buttons["toast.action"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "після видалення пропонується скасування")
        undo.tap()

        XCTAssertEqual(percent.label, "25%", "порція повернулась разом з прогресом")
        XCTAssertTrue(app.staticTexts["500 мл"].exists, "і повернулась в історію")
    }

    func testCustomAmountSheetAddsPortion() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.add.custom"].tap()
        let value = app.staticTexts["custom.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "300")

        app.buttons["500"].tap()
        XCTAssertEqual(value.label, "500")

        app.buttons["custom.confirm"].tap()
        XCTAssertEqual(app.staticTexts["home.percent"].label, "25%")
    }

    func testGoalChangeInSettingsRecalculatesProgress() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        app.buttons["home.add.500"].tap()

        app.buttons["home.settings"].tap()
        let goal = app.staticTexts["settings.goal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.label, "2.0 л")

        app.buttons["+"].firstMatch.tap()
        XCTAssertEqual(goal.label, "2.2 л", "2000 + 250 мл = 2250 → «2.2 л»")

        app.buttons["Готово"].tap()
        XCTAssertEqual(app.staticTexts["home.percent"].label, "22%", "прогрес перерахований під нову норму")
    }

    // MARK: - Навігація

    func testNavigationToProgressAndAchievements() {
        let app = launch(["--uitest-demo"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 20))

        app.buttons["home.level"].tap()
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 5))

        app.buttons["progress.allAchievements"].tap()
        XCTAssertTrue(app.staticTexts["Прогрес нагород"].waitForExistence(timeout: 5))

        app.buttons["Всі"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Перша крапля"].waitForExistence(timeout: 5))
    }

    func testStatsScreenShowsAllCards() {
        let app = launch(["--uitest-demo", "--start-screen", "stats"])
        XCTAssertTrue(app.staticTexts["Норма води"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Рівномірність за день"].exists)
        XCTAssertTrue(app.staticTexts["Обʼєм по днях"].exists)

        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Календар пиття"].exists)

        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Типова доба — медіана і розкид"].waitForExistence(timeout: 5))

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Коли ти пʼєш"].waitForExistence(timeout: 5))
    }

    // MARK: - Тема

    func testDarkThemeToggle() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.staticTexts["Темна тема"].waitForExistence(timeout: 5))
        app.buttons["settings.theme"].tap()
        app.buttons["Готово"].tap()

        XCTAssertTrue(app.staticTexts["home.percent"].exists, "екран лишається робочим у темній темі")
    }
}
