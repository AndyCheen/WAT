import XCTest

/// Вікно «Шлях рівнів» (WAT-44, SPEC-PRIZES §16.17). Демо чекає по одному вузлу кожного виду —
/// останній вибір і останній таємний приз (`FixtureSeeder.settleLevelRoad`). Номери рівнів залежать від
/// дати запуску, тож вузли шукаємо за префіксом ідентифікатора.
final class LevelRoadUITests: XCTestCase {

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

    private func element(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .firstMatch
    }

    /// Рівень вузла з ідентифікатора `levelRoad.mystery.15` / `levelRoad.choice.17.xp.double`.
    private func level(of element: XCUIElement, prefix: String) -> String {
        String(element.identifier.dropFirst(prefix.count).prefix { $0.isNumber })
    }

    func testLevelOpensFullScreenWindowFocusedOnPendingPrize() {
        let app = launch(["--uitest-demo", "--start-screen", "progress"])
        let level = app.buttons["progress.level"]
        XCTAssertTrue(level.waitForExistence(timeout: 20))
        level.tap()

        let road = app.scrollViews["levelRoad.screen"]
        XCTAssertTrue(road.waitForExistence(timeout: 5))
        // На весь екран, а не пів-шторкою: рамка вікна — уся ширина й більша частина висоти.
        XCTAssertEqual(road.frame.width, app.windows.firstMatch.frame.width, accuracy: 1)
        XCTAssertGreaterThan(road.frame.height, app.windows.firstMatch.frame.height * 0.7)

        // Фокус — на найранішому, що чекає: у демо це таємний приз, і його видно без прокрутки.
        let open = element(app, prefix: "levelRoad.mystery.")
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(open.isHittable, "вікно відкривається вже прокрученим до призу, що чекає")

        app.buttons["levelRoad.close"].tap()
        XCTAssertTrue(road.waitForNonExistence(timeout: 5))
        XCTAssertTrue(level.isHittable, "закриття повертає на 3f")
    }

    func testChoiceIsTakenOnceAndCollapses() {
        let app = launch(["--uitest-demo", "--start-screen", "level-road"])
        XCTAssertTrue(app.scrollViews["levelRoad.screen"].waitForExistence(timeout: 20))

        let freeze = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'levelRoad.choice.' AND identifier ENDSWITH '.streak.freeze'")).firstMatch
        XCTAssertTrue(freeze.waitForExistence(timeout: 5))
        let nodeLevel = level(of: freeze, prefix: "levelRoad.choice.")
        for _ in 0..<4 where !freeze.isHittable { app.scrollViews["levelRoad.screen"].swipeUp() }

        let claim = app.buttons["levelRoad.choice.\(nodeLevel).claim"]
        XCTAssertFalse(claim.isEnabled, "без вибору «Забрати» неактивна")
        freeze.tap()
        XCTAssertTrue(claim.isEnabled)
        claim.tap()

        // Після підтвердження картка згортається в «Обрано з двох».
        let node = app.descendants(matching: .any)["levelRoad.node.\(nodeLevel)"]
        XCTAssertTrue(node.waitForExistence(timeout: 5))
        XCTAssertTrue(node.label.contains("обрано з двох"), node.label)
        XCTAssertFalse(freeze.exists, "вибір остаточний — варіантів більше немає")
    }

    func testMysteryRevealsPredeterminedPrize() {
        let app = launch(["--uitest-demo", "--start-screen", "level-road"])
        let open = element(app, prefix: "levelRoad.mystery.")
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        let nodeLevel = level(of: open, prefix: "levelRoad.mystery.")
        open.tap()

        let done = app.buttons["levelRoad.reveal.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let shown = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: done)
        wait(for: [shown], timeout: 5)
        done.tap()

        let node = app.descendants(matching: .any)["levelRoad.node.\(nodeLevel)"]
        XCTAssertTrue(node.waitForExistence(timeout: 5))
        XCTAssertTrue(node.label.contains("з таємного призу"), node.label)
        XCTAssertFalse(app.buttons["levelRoad.mystery.\(nodeLevel)"].exists, "відкривається один раз")
    }

    func testXPGuideOpensAndCloses() {
        let app = launch(["--uitest-demo", "--start-screen", "level-road"])
        let help = app.buttons["levelRoad.guideButton"]
        XCTAssertTrue(help.waitForExistence(timeout: 20))
        help.tap()

        let title = app.staticTexts["levelRoad.guide"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Вода, кожні 250 мл"].exists, "баланс за замовчуванням з Config/Balance.xcconfig")

        app.buttons["levelRoad.guide.close"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
    }
}
