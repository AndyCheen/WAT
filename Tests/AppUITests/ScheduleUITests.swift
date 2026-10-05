import XCTest

/// E2E вікна «Графік дня» (WAT-41, SPEC-NOTIFICATIONS §27). `--seed-schedule-shift` — 10 днів із першою
/// склянкою ≈ 06:30, і вікно з'являється само; `--start-screen schedule-suggestion[:варіант]` — одразу,
/// повз правило частоти.
final class ScheduleUITests: XCTestCase {

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

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: timeout)
    }

    /// Тост справді на екрані, а не лише в дереві.
    private func assertToast(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let toast = app.staticTexts["toast.message"]
        XCTAssertTrue(toast.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(toast.label, text, file: file, line: line)
        XCTAssertTrue(toast.isHittable, "тост у межах екрана", file: file, line: line)
    }

    private func openNotificationsScreen(_ app: XCUIApplication) {
        app.buttons["home.settings"].tap()
        let row = app.buttons["settings.notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["notifications.master"].waitForExistence(timeout: 5))
    }

    /// Критерій приймання: 10 днів із першою порцією ≈ 06:30 при підйомі 08:00 — на відкритті вікно з 06:30;
    /// «Так» міняє підйом.
    func testSeededShiftOffersWakeOnOpen() {
        let app = launch(["--uitest-empty", "--seed-schedule-shift"])
        let title = app.staticTexts["schedule.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(title.isHittable, "вікно видно, а не просто є в дереві")
        XCTAssertEqual(title.label, "Змінити підйом?")
        XCTAssertEqual(app.descendants(matching: .any)["schedule.change.wake"].label, "Підйом: було 08:00, стане 06:30")

        app.buttons["schedule.accept"].tap()
        waitForDisappearance(title)
        assertToast(app, "Графік оновлено: 06:30–22:00")

        openNotificationsScreen(app)
        XCTAssertEqual(app.staticTexts["notifications.wake"].label, "06:30")
    }

    /// «Ні, залишити» — вікно закривається без тоста, графік той самий.
    func testDeclineKeepsSchedule() {
        let app = launch(["--uitest-empty", "--start-screen", "schedule-suggestion"])
        let decline = app.buttons["schedule.decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 15))
        decline.tap()
        waitForDisappearance(decline)
        XCTAssertFalse(app.staticTexts["toast.message"].waitForExistence(timeout: 2))

        openNotificationsScreen(app)
        XCTAssertEqual(app.staticTexts["notifications.wake"].label, "08:00")
    }

    /// «Налаштувати» — кроки часу прямо у вікні, без переходу в налаштування.
    func testAdjustInsideTheWindow() {
        let app = launch(["--uitest-empty", "--start-screen", "schedule-suggestion"])
        let adjust = app.buttons["schedule.adjust"]
        XCTAssertTrue(adjust.waitForExistence(timeout: 15))
        adjust.tap()

        let plus = app.buttons["schedule.wake.plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertEqual(app.staticTexts["schedule.wake"].value as? String, "06:45")
        XCTAssertFalse(adjust.exists, "у режимі кроків «Налаштувати» вже не потрібне")

        app.buttons["schedule.accept"].tap()
        assertToast(app, "Графік оновлено: 06:45–22:00")
    }

    /// Зсув лише у вихідні — «Так» вмикає окремий розклад вихідних, будні лишаються.
    func testWeekendSuggestionEnablesWeekendSchedule() {
        let app = launch(["--uitest-empty", "--start-screen", "schedule-suggestion:weekend"])
        let scope = app.staticTexts["schedule.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 15))
        XCTAssertEqual(scope.label, "Лише вихідні")

        app.buttons["schedule.accept"].tap()
        assertToast(app, "Графік вихідних оновлено: 10:00–22:00")

        openNotificationsScreen(app)
        XCTAssertEqual(app.staticTexts["notifications.wake"].label, "08:00")
        XCTAssertEqual(app.staticTexts["notifications.weekendWake"].label, "10:00")
    }

    /// Не поверх іншого: застосунок відкрили тапом по ранковій склянці — людина прийшла по воду.
    func testNoWindowOverNotificationTap() {
        let app = launch(["--uitest-empty", "--seed-schedule-shift", "--notification-tap", "morning"])
        XCTAssertTrue(app.buttons["glass.calibrate.done"].waitForExistence(timeout: 15), "перше відкриття «Склянки» — калібрування")
        XCTAssertFalse(app.staticTexts["schedule.title"].waitForExistence(timeout: 3))
    }
}
