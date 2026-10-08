import XCTest

/// Віджети (WAT-30, SPEC-WIDGETS). Домашній екран і процес WidgetKit у XCUITest нестабільні, тож
/// в'юшки — у DEBUG-галереї (`--start-screen widgets`), дії кнопок — прапорцем `--widget-action`
/// (той самий `AppServices.perform`, що й інтент у процесі застосунку), переходи — URL-схемою.
final class WidgetsUITests: XCTestCase {

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

    /// День, а не ніч: віджети показують стан доби, і без фіксованого годинника тест залежав би від часу запуску.
    private static let noon = ["--uitest-now", "2026-10-08T12:00:00+03:00"]

    func testGalleryShowsEveryWidget() {
        let app = launch(["--uitest-empty", "--start-screen", "widgets"] + Self.noon)
        let first = app.staticTexts["widgetGallery.title.today"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(first.isHittable)
        for id in ["dayPart", "rhythm", "reserve.water", "reserve.flask", "quickAdd", "button", "progress", "overview"] {
            XCTAssertTrue(app.staticTexts["widgetGallery.title.\(id)"].exists, id)
        }
        // Порожній день: «Запас води» просить почати.
        XCTAssertTrue(app.staticTexts["Почни зі склянки"].exists)
    }

    /// Тап по кнопці віджета: порція без відкриття шторок, на місці кнопок — «Скасувати»; скасування
    /// прибирає порцію й повертає кнопки.
    func testWidgetButtonAndUndo() {
        let app = launch(["--uitest-empty", "--start-screen", "widgets"] + Self.noon)
        // «+250» — і віджет «Кнопка», і кругла кнопка екрана блокування: досить першої.
        let add = app.buttons["widget.add.250"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()

        let undo = app.buttons["widget.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["+250 мл"].firstMatch.exists)
        undo.tap()

        XCTAssertTrue(app.buttons["widget.add.250"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["widget.undo"].exists)
    }

    /// `--widget-action` — порція з віджета доходить до головного: та сама доба, той самий відсоток.
    func testWidgetActionReachesHome() {
        let app = launch(["--uitest-empty", "--widget-action", "add:500"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["500 мл"].waitForExistence(timeout: 5), "порція в історії")
        XCTAssertEqual(percent.label, "25%")
    }

    func testWidgetUndoFlag() {
        let app = launch(["--uitest-empty", "--widget-action", "add:500,undo"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 15))
        XCTAssertEqual(percent.label, "0%")
        XCTAssertFalse(app.staticTexts["500 мл"].exists)
    }

    /// Тапи по віджетах — `watertracker://…`: статистика, прогрес, шторка «Інше».
    func testLinksOpenScreens() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        XCTAssertTrue(open("watertracker://stats", in: app, expecting: app.staticTexts["Норма води"]))
        XCTAssertTrue(open("watertracker://progress", in: app, expecting: app.buttons["progress.level"]))
        XCTAssertTrue(open("watertracker://custom", in: app, expecting: app.staticTexts["custom.value"]))
    }

    /// URL ззовні iOS підтверджує діалогом «Відкрити у програмі «Вода»?» — не щоразу й не одразу. Тап по
    /// віджету такого діалогу не має, тож тест просто проходить повз нього, поки не з'явиться екран.
    private func open(_ url: String, in app: XCUIApplication, expecting element: XCUIElement) -> Bool {
        XCUIDevice.shared.system.open(URL(string: url)!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if element.exists { return true }
            for title in ["Відкрити", "Open"] where springboard.buttons[title].exists {
                springboard.buttons[title].tap()
            }
            _ = element.waitForExistence(timeout: 0.5)
        }
        return element.exists
    }
}
