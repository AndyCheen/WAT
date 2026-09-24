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

    func testCompletedQuestsHideBehindToggle() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        // Денні слоти детерміновані: «Випити денну норму» + «Додати 4 записи».
        let questRow = app.staticTexts["Додати 4 записи"]
        let toggle = app.buttons["home.tasks.toggleCompleted"]
        XCTAssertTrue(questRow.exists, "невиконане завдання видно одразу")
        XCTAssertFalse(toggle.exists, "ховати нема чого, доки нічого не виконано")

        // 4 × 500 мл закривають обидва завдання: і норму, і кількість записів.
        for _ in 0..<4 { app.buttons["home.add.500"].tap() }

        XCTAssertFalse(questRow.exists, "виконане завдання зникає зі списку")
        XCTAssertTrue(app.staticTexts["Усі завдання виконані 🎉"].exists)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        toggle.tap()
        XCTAssertTrue(questRow.waitForExistence(timeout: 5), "кнопка повертає виконані завдання")
        // Сам факт існування елемента нічого не доводить — рядок може бути за межею екрана.
        XCTAssertTrue(questRow.isHittable, "рядок справді видно")

        toggle.tap()
        XCTAssertFalse(questRow.exists, "повторне натискання ховає їх знову")
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
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "після видалення пропонується скасування")
        // `waitForExistence` каже лише, що елемент є в ієрархії. Тост показується поверх
        // екрана з переходом знизу — якщо він застрягне за межею екрана, наявність
        // лишиться true, а користувач нічого не побачить. Ловимо саме це.
        XCTAssertTrue(undo.isHittable, "тост має бути доступний для дотику, а не просто існувати")
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(undo.frame),
            "тост має бути в межах екрана"
        )
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
        XCTAssertTrue(app.otherElements["achievements.counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["achievements.tile.first.drop"].exists)
    }

    // MARK: - Досягнення (SPEC-ACHIEVEMENTS §13)

    func testStateChipsSliceTheGridButNotTheCounter() {
        let app = launch(["--uitest-demo", "--start-screen", "achievements"])
        let counter = app.otherElements["achievements.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        let counterValue = counter.value as? String

        app.buttons["achievements.state.inProgress"].tap()
        XCTAssertTrue(app.buttons["achievements.tile.streak.7"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["achievements.tile.first.drop"].exists, "відкрите не «в процесі»")
        XCTAssertEqual(counter.value as? String, counterValue, "лічильник глобальний — чип його не змінює")

        app.buttons["achievements.state.unlocked"].tap()
        XCTAssertTrue(app.buttons["achievements.tile.first.drop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["achievements.tile.streak.7"].exists)
    }

    func testCategoryMenuFiltersAndChipClearsIt() {
        let app = launch(["--uitest-demo", "--start-screen", "achievements"])
        let categoryButton = app.buttons["achievements.category"]
        XCTAssertTrue(categoryButton.waitForExistence(timeout: 20))

        categoryButton.tap()
        let streaks = app.buttons["achievements.category.option.streak"]
        XCTAssertTrue(streaks.waitForExistence(timeout: 5))
        // Меню розкривається з кнопки вгорі, а не шторкою знизу екрана.
        XCTAssertLessThan(streaks.frame.minY, app.windows.firstMatch.frame.midY, "меню — під кнопкою, не знизу")
        streaks.tap()

        let clear = app.buttons["achievements.category.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "активна категорія — чип із хрестиком")
        XCTAssertFalse(streaks.exists, "вибір закриває меню")
        XCTAssertTrue(app.buttons["achievements.tile.streak.3"].exists)
        XCTAssertFalse(app.buttons["achievements.tile.first.drop"].exists)

        clear.tap()
        XCTAssertTrue(app.buttons["achievements.tile.first.drop"].waitForExistence(timeout: 5), "хрестик повертає «Всі»")
    }

    func testBadgeOnProgressOpensTheDetailCard() {
        let app = launch(["--uitest-demo", "--start-screen", "progress"])
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 20))

        // Блок досягнень — останній на екрані, під призами.
        let badge = app.buttons["progress.achievements.badge.streak.7"]
        for _ in 0..<8 where !(badge.exists && badge.isHittable) { app.swipeUp() }
        XCTAssertTrue(badge.isHittable, "бейдж у процесі потрапляє у вітрину")
        badge.tap()

        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "Тиждень поспіль")

        app.buttons["achievements.detail.close"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 1), "хрестик закриває картку")
    }

    func testFirstIntakeShowsAchievementToastLeadingToTheCard() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.add.200"].tap()

        let message = app.staticTexts["toast.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 3))
        XCTAssertEqual(message.label, "🏅 Досягнення: Перша крапля")
        let action = app.buttons["toast.action"]
        XCTAssertTrue(action.isHittable, "тост має бути в межах екрана, а не просто існувати")
        action.tap()

        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "«Подивитись» відкриває картку одразу")
        XCTAssertEqual(card.label, "Перша крапля")
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

    // MARK: - Призи (SPEC-PRIZES §11, §15)

    /// Демо: учора пропущено після серії, у запасі ≥ 2 заморозки. Перша заморожує вчора,
    /// після цього вчора зараховано — і друга вже заморожує сьогодні (§6.2).
    func testFreezeButtonNamesTheDayItFreezes() {
        let app = launch(["--uitest-demo", "--start-screen", "progress"])
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 20))

        let row = app.buttons["progress.prizes.row.streak.freeze"]
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "стос заморозок видно на 3f")
        row.tap()

        let action = app.buttons["prizes.detail.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Заморозити вчора")
        action.tap()
        XCTAssertFalse(app.otherElements["prizes.detail"].waitForExistence(timeout: 1), "після дії картка закривається")

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Заморозити сьогодні")

        app.buttons["prizes.detail.close"].tap()
        XCTAssertFalse(action.waitForExistence(timeout: 1), "хрестик закриває картку")
    }

    func testBoostActivationShowsActiveCardOnPrizesScreen() {
        let app = launch(["--uitest-demo", "--start-screen", "prizes"])
        let row = app.buttons["prizes.row.xp.double"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["prizes.active"].exists, "у демо нічого не діє")

        row.tap()
        let action = app.buttons["prizes.detail.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.label.hasPrefix("Увімкнути на "), "кнопка каже, скільки діятиме: \(action.label)")
        action.tap()

        let active = app.buttons["prizes.active"]
        XCTAssertTrue(active.waitForExistence(timeout: 5), "буст зʼявився в «Діє зараз»")
        XCTAssertTrue(active.isHittable)
        active.tap()
        XCTAssertTrue(app.otherElements["prizes.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(action.exists, "у діючого призу кнопки немає")
    }

    func testAllPrizesLeadsFromProgressToPrizesScreen() {
        let app = launch(["--uitest-demo", "--start-screen", "progress"])
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 20))

        let all = app.buttons["progress.allPrizes"]
        for _ in 0..<6 where !(all.exists && all.isHittable) { app.swipeUp() }
        all.tap()

        XCTAssertTrue(app.buttons["prizes.row.streak.freeze"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["prizes.empty"].exists)
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
