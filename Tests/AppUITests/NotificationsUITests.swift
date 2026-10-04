import XCTest

/// E2E модуля «Сповіщення» (SPEC-NOTIFICATIONS §16.11). Реальні сповіщення в симуляторі
/// нестабільні, тож центр під `--uitest-*` — у пам'яті: дозвіл задає `--notifications-auth`,
/// тап імітує `--notification-tap`, а що саме заплановано, показує DEBUG-екран «План сповіщень».
final class NotificationsUITests: XCTestCase {

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

    /// На першому запуску системного запиту немає; після першої порції — шторка з поясненням,
    /// і з'являється вона після тоста «Перша крапля», а не поверх нього (критерій §19.1).
    func testPermissionSheetFollowsFirstIntake() {
        let app = launch(["--uitest-empty", "--notifications-auth", "notDetermined"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["permission.enable"].exists, "на першому запуску запиту немає")

        app.buttons["home.add.200"].tap()

        let enable = app.buttons["permission.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 8))
        XCTAssertTrue(enable.isHittable, "шторку видно, а не просто є в дереві")
        enable.tap()
        waitForDisappearance(enable)
    }

    /// «Не зараз» — наступного разу через 3 дні, а не на кожну порцію.
    func testPermissionLaterIsNotRepeatedOnNextIntake() {
        let app = launch(["--uitest-empty", "--notifications-auth", "notDetermined"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        app.buttons["home.add.200"].tap()

        let later = app.buttons["permission.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 8))
        later.tap()
        waitForDisappearance(later)

        app.buttons["home.add.200"].tap()
        XCTAssertFalse(app.buttons["permission.enable"].waitForExistence(timeout: 5))
    }

    /// Рядок «Нагадування» в налаштуваннях веде на екран «Сповіщення» (§15.1).
    func testNotificationsScreenFromSettings() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        app.buttons["home.settings"].tap()
        let row = app.buttons["settings.notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.buttons["notifications.master"].waitForExistence(timeout: 5))

        app.buttons["notifications.glass.plus"].tap()
        XCTAssertEqual(app.staticTexts["notifications.glass"].label, "275 мл", "крок склянки — 25 мл")

        app.buttons["notifications.wake.plus"].tap()
        XCTAssertEqual(app.staticTexts["notifications.wake"].label, "08:15", "крок часу — 15 хв")

        let add = app.buttons["notifications.quiet.add"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        add.tap()
        let from = app.staticTexts["notifications.quiet.0.from"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        XCTAssertEqual(from.label, "10:00")
        app.buttons["notifications.quiet.0.delete"].tap()
        waitForDisappearance(from)

        let frequency = app.buttons["Частіше"]
        for _ in 0..<4 where !frequency.isHittable { app.swipeUp() }
        XCTAssertTrue(frequency.isHittable)
        app.buttons["notifications.reminders"].tap()
        waitForDisappearance(frequency)
    }

    /// Без дозволу екран це показує й веде в налаштування iOS (критерій §19.2).
    func testDeniedPermissionShowsBanner() {
        let app = launch(["--uitest-empty", "--notifications-auth", "denied", "--start-screen", "notifications"])
        let banner = app.staticTexts["notifications.denied"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["notifications.denied.action"].isHittable)
    }

    /// Тап по нагадуванню — головний зі шторкою «Інше» на типову порцію (§6.4).
    func testReminderTapOpensCustomAmountWithTypicalPortion() {
        let app = launch(["--uitest-empty", "--notification-tap", "reminder"])
        let value = app.staticTexts["custom.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 15))
        XCTAssertEqual(value.label, "250", "без історії P = моя склянка")
        XCTAssertTrue(app.staticTexts["Скільки води?"].exists, "звертання без роду (§14.1)")
    }

    /// Тап по порятунку серії відкриває картку заморозки — у самому сповіщенні кнопки
    /// «Заморозити» немає (критерій §19.11).
    func testRescueTapOpensFreezeCard() {
        let app = launch(["--uitest-demo", "--notification-tap", "rescue"])
        let action = app.buttons["prizes.detail.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 20))
        XCTAssertEqual(action.label, "Заморозити вчора", "у демо вчора пропущено після закритого позавчора")
    }

    /// DEBUG-екран «План сповіщень»: о 07:00 без порцій перше нагадування — 09:42, як у «подорожі» з §6.1.
    func testDebugPlanListsReminderChain() {
        let app = launch([
            "--uitest-empty", "--uitest-now", "2026-10-01T07:00:00+03:00", "--start-screen", "notification-plan"
        ])
        XCTAssertTrue(app.staticTexts["plan.row.wt.morning.2026-10-01"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["plan.row.wt.reminder.2026-10-01.0942"].exists)
    }
}
