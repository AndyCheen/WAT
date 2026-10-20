import XCTest

/// E2E онбордингу (WAT-56, SPEC-ONBOARDING). Під `--uitest-*` він сам не відкривається — `--start-screen onboarding`
/// відкриває перший запуск, а повторний прохід — рядок «Підібрати під себе» в «Налаштуваннях».
final class OnboardingUITests: XCTestCase {

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

    private func title(_ app: XCUIApplication, _ step: String) -> XCUIElement {
        app.staticTexts["onboarding.title.\(step)"]
    }

    /// «Далі» й чекати наступний крок — заголовок кроку визначає, де ми.
    private func next(_ app: XCUIApplication, to step: String, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(title(app, step).waitForExistence(timeout: 5), "крок \(step)", file: file, line: line)
    }

    private func openRevisit(_ app: XCUIApplication) {
        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let row = app.buttons["settings.onboarding"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(title(app, "hello").waitForExistence(timeout: 5))
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: timeout)
    }

    /// Перший запуск до кінця з типовими відповідями: норма 2.55 л, після фінішу — головний.
    func testFirstRunWithTypicalAnswersSetsGoal() {
        let app = launch(["--uitest-empty", "--start-screen", "onboarding"])
        XCTAssertTrue(title(app, "hello").waitForExistence(timeout: 15))
        for step in ["units", "gender", "age", "weight", "activity", "goal", "day", "rhythm", "glass", "reminders", "done"] {
            next(app, to: step)
        }
        let goal = app.descendants(matching: .any)["onboarding.summary.goal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertTrue(goal.label.contains("2.55 л на день"), goal.label)

        app.buttons["onboarding.finish"].tap()
        waitForDisappearance(title(app, "done"))
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
    }

    /// «Пропустити» на вітанні — одразу головний.
    func testSkipFromHello() {
        let app = launch(["--uitest-empty", "--start-screen", "onboarding"])
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
        waitForDisappearance(title(app, "hello"))
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
    }

    /// «Жінка» відкриває стан, і застереження «не медична порада» докручується в поле зору.
    func testFemaleShowsConditionWithDisclaimer() {
        let app = launch(["--uitest-empty", "--start-screen", "onboarding"])
        XCTAssertTrue(title(app, "hello").waitForExistence(timeout: 15))
        next(app, to: "units")
        next(app, to: "gender")
        app.buttons["onboarding.gender.female"].tap()
        let disclaimer = app.descendants(matching: .any)["onboarding.condition.disclaimer"]
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 5))
        // Панель докручується до низу трохи згодом — після появи картки стану.
        let visible = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: disclaimer)
        wait(for: [visible], timeout: 5)
        XCTAssertTrue(app.buttons["onboarding.condition.pregnancy"].exists)
    }

    /// Повторний прохід: змінена вага — у «Що зміниться», після «Зберегти» — назад у «Налаштування».
    func testRevisitListsChangesAndSaves() {
        let app = launch(["--uitest-empty"])
        openRevisit(app)
        for step in ["units", "gender", "age", "weight"] { next(app, to: step) }
        let plus = app.buttons["onboarding.weight.plus"]
        plus.tap()
        plus.tap()
        for step in ["activity", "goal", "day", "rhythm", "glass", "reminders", "done"] { next(app, to: step) }

        let weight = app.descendants(matching: .any)["onboarding.change.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(weight.label.contains("72 кг"), weight.label)

        app.buttons["onboarding.save"].tap()
        waitForDisappearance(title(app, "done"))
        XCTAssertTrue(app.buttons["settings.onboarding"].waitForExistence(timeout: 5))
    }

    /// ✕ після зміни — «Вийти без змін?»; «Вийти» нічого не записує.
    func testRevisitCloseWithChangesAsks() {
        let app = launch(["--uitest-empty"])
        openRevisit(app)
        next(app, to: "units")
        app.buttons["onboarding.units.volume.1"].tap()
        app.buttons["onboarding.close"].tap()
        let confirm = app.buttons["onboarding.exit.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        waitForDisappearance(title(app, "units"))
        XCTAssertTrue(app.buttons["settings.onboarding"].waitForExistence(timeout: 5))
    }

    /// Альтернативний дизайн за тимчасовим перемикачем — ті самі кроки й та сама норма.
    func testStepsDesignShowsSameGoal() {
        let app = launch(["--uitest-empty", "--start-screen", "onboarding", "--onboarding-design", "steps"])
        XCTAssertTrue(title(app, "hello").waitForExistence(timeout: 15))
        for step in ["units", "gender", "age", "weight", "activity", "goal"] { next(app, to: step) }
        let value = app.staticTexts["onboarding.goal.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "2.55")
    }
}
