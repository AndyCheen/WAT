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

    // MARK: - Етап B (WAT-37)

    /// Тап по ранковій склянці — окреме вікно «Склянка»: спершу один раз «скільки в твоїй
    /// склянці?», далі частка й запис; вікно закривається само, порція — на головному (§7.1).
    func testMorningTapOpensGlassWindow() {
        let app = launch(["--uitest-empty", "--notification-tap", "morning"])
        let calibrate = app.buttons["glass.calibrate.300"]
        XCTAssertTrue(calibrate.waitForExistence(timeout: 15))
        XCTAssertTrue(calibrate.isHittable, "вікно на весь екран, а не лише в дереві")
        calibrate.tap()
        app.buttons["glass.calibrate.done"].tap()

        let value = app.staticTexts["glass.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.label, "300", "за замовчуванням — повна склянка")

        app.buttons["glass.chip.50"].tap()
        XCTAssertEqual(value.label, "150")
        let control = app.otherElements["glass.control"]
        XCTAssertEqual(control.value as? String, "150 мл, пів склянки", "VoiceOver: об'єм і частка")

        app.buttons["glass.record"].tap()
        waitForDisappearance(app.buttons["glass.record"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 5))
        XCTAssertTrue(percent.label.hasPrefix("8"), "150 мл з 2000 — 8 %: \(percent.label)")
    }

    /// Тап по звіту — історія: гортається тапом праворуч, на останньому слайді — «Готово» (§11.3).
    func testReportTapOpensStory() {
        let app = launch(["--uitest-demo", "--notification-tap", "report"])
        let close = app.buttons["report.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        XCTAssertTrue(close.isHittable)
        let headline = app.staticTexts["report.headline"].firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        let first = headline.label

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6)).tap()
        XCTAssertTrue(app.staticTexts["report.headline"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["report.headline"].firstMatch.label, first, "тап праворуч — наступний слайд")

        let done = app.buttons["report.done"]
        for _ in 0..<8 where !done.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6)).tap()
        }
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["report.previous"].isHittable)
        done.tap()
        waitForDisappearance(close)
    }

    /// Рядки етапу B на екрані «Сповіщення»: чекпоінти й звіти з днем тижня (§15.1).
    func testNotificationsScreenHasStageBRows() {
        let app = launch(["--uitest-empty", "--start-screen", "notifications"])
        XCTAssertTrue(app.buttons["notifications.checkpoints"].waitForExistence(timeout: 15))

        let weekday = app.buttons["notifications.reportWeekday.0"]
        for _ in 0..<6 where !weekday.isHittable { app.swipeUp() }
        XCTAssertTrue(weekday.isHittable)
        XCTAssertTrue(weekday.isSelected, "типово — понеділок")
        app.buttons["notifications.reportWeekday.6"].tap()
        XCTAssertTrue(app.buttons["notifications.reportWeekday.6"].isSelected)
        XCTAssertFalse(weekday.isSelected, "день тижня — один")

        XCTAssertEqual(app.staticTexts["notifications.reportWeekTime"].label, "10:00")
        app.buttons["notifications.reportWeek"].tap()
        waitForDisappearance(app.staticTexts["notifications.reportWeekTime"])
        XCTAssertTrue(app.buttons["notifications.reportDay"].exists)
        XCTAssertTrue(app.buttons["notifications.reportMonth"].exists)
    }
}
