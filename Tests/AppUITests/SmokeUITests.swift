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
        // «Перша крапля» — вікно на весь екран (WAT-60): головне під ним для XCUITest не досяжне.
        dismissCelebrationIfPresent(app)

        XCTAssertEqual(percent.label, "25%", "500 мл від норми 2000 мл")
        XCTAssertTrue(app.staticTexts["500 мл"].exists, "порція зʼявилась в історії")
    }

    /// Капсула частини доби (WAT-40): годинник стоїть на 11:25, тож обидві порції — о 11:25.
    /// 550 з 689 мл до 12:00 — «ще 150 мл», 35 хв; порція 200 мл закриває частину одразу.
    func testDayPartPillCountsDownAndCloses() {
        let app = launch(["--uitest-empty", "--uitest-now", "2026-10-01T11:25:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        let pill = app.descendants(matching: .any)["home.dayPart"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "частина доби триває — капсула є і без порцій")
        XCTAssertEqual(pill.label, "До 12:00 бракує 700 мл, лишилось 35 хвилин")

        let confirm = app.buttons["custom.confirm"]
        app.buttons["home.add.custom"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()                                // 300 мл — значення за замовчуванням
        // Шторка зникає з анімацією: тап до її кінця влучив би в неї, а не в кнопку.
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        dismissCelebrationIfPresent(app)             // «Перша крапля» і «Своя мірка»
        app.buttons["home.add.custom"].tap()
        let chip = app.buttons["250"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))

        XCTAssertEqual(pill.label, "До 12:00 бракує 150 мл, лишилось 35 хвилин")
        XCTAssertTrue(pill.isHittable, "капсулу справді видно, а не лише в дереві")

        app.buttons["home.add.200"].tap()
        dismissCelebrationIfPresent(app, timeout: 2)
        XCTAssertEqual(pill.label, "Ранок і полудень закрито", "порція, що закриває частину, одразу дає ✓")
    }

    /// «Ритм дня» (WAT-42): вимикання прибирає капсулу частини доби, разово пропонує «Рівні інтервали»,
    /// а на екрані «Сповіщення» зникає перемикач чекпоінтів — їх без ритму немає зовсім.
    func testDayRhythmToggleSwitchesToPlainDailyGoal() {
        let app = launch(["--uitest-empty", "--uitest-now", "2026-10-01T11:25:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        let pill = app.descendants(matching: .any)["home.dayPart"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))

        app.buttons["home.settings"].tap()
        let toggle = app.buttons["settings.dayRhythm"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["Просто норма за день"].waitForExistence(timeout: 5))

        let offer = app.buttons["settings.intervalOffer.action"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5), "«За темпом» теж спирається на частини доби")
        XCTAssertTrue(offer.isHittable)
        offer.tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5))

        app.buttons["nav.back"].tap()
        XCTAssertTrue(pill.waitForNonExistence(timeout: 5), "капсули частини доби немає")

        app.buttons["home.settings"].tap()
        let row = app.buttons["settings.notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["notifications.master"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["notifications.checkpoints"].exists)
        XCTAssertFalse(app.buttons["Частіше"].exists, "нагадування перейшли на рівні інтервали")
    }

    // MARK: - Завдання (SPEC-QUESTS §9)

    /// Рядок завдання — один елемент доступності з ідентифікатором `quest.row.<ключ>`.
    private func questRow(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["quest.row.\(key)"]
    }

    /// Порція закриває «Склянку після підйому»: рядок святкує й згортається в «Виконані · 1», а кнопка повертає
    /// його на екран. Завдання — повз пікер (`--quests`): вибір пікера залежить від зерна профілю й дня.
    func testCompletedQuestCelebratesAndHidesBehindToggle() {
        let app = launch(["--uitest-empty", "--quests", "daily:daily.wakeGlass,daily.glasses",
                          "--uitest-now", "2026-10-01T07:30:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        // Підйом о 08:00 — дедлайн о 09:00; порція до підйому теж рахується.
        let wake = questRow(app, "daily.wakeGlass")
        let toggle = app.buttons["home.tasks.toggleCompleted"]
        XCTAssertTrue(wake.waitForExistence(timeout: 5), "невиконане завдання видно одразу")
        XCTAssertEqual(wake.label, "Склянка після підйому, ще 250 мл, 15 XP")
        XCTAssertTrue(questRow(app, "daily.glasses").exists)
        XCTAssertTrue(app.staticTexts["home.tasks.today"].exists)
        XCTAssertFalse(toggle.exists, "ховати нема чого, доки нічого не виконано")

        app.buttons["home.add.500"].tap()
        // «Перша крапля» — вікно на весь екран; рядок святкує після нього.
        dismissCelebrationIfPresent(app)
        XCTAssertTrue(wake.waitForNonExistence(timeout: 5), "свято в рядку — і рядок згортається")
        XCTAssertTrue(questRow(app, "daily.glasses").exists, "невиконане лишається")
        XCTAssertFalse(app.staticTexts["Усе на сьогодні 🎉"].exists, "виконано лише одне з двох")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Виконані · 1")

        toggle.tap()
        XCTAssertTrue(wake.waitForExistence(timeout: 5), "кнопка повертає виконані завдання")
        // Сам факт існування елемента нічого не доводить — рядок може бути за межею екрана.
        XCTAssertTrue(wake.isHittable, "рядок справді видно")
        XCTAssertEqual(wake.label, "Склянка після підйому, виконано, 15 XP")

        toggle.tap()
        XCTAssertTrue(wake.waitForNonExistence(timeout: 5), "повторне натискання ховає їх знову")
    }

    /// Після дедлайну невиконане щоденне тихо зникає: обидва прострочені — секції «Сьогодні» немає зовсім,
    /// без «провалено» й без «Усе на сьогодні».
    func testOverdueDailyQuestsLeaveQuietly() {
        let app = launch(["--uitest-empty", "--quests", "daily:daily.wakeGlass,daily.quarterBy;weekly:weekly.goalDays=3",
                          "--uitest-now", "2026-10-01T11:30:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        // Тижневе — щоб блок був на екрані і відсутність «Сьогодні» щось доводила.
        let weekly = questRow(app, "weekly.goalDays")
        XCTAssertTrue(weekly.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.tasks.week"].exists)
        XCTAssertEqual(app.staticTexts["home.tasks.week"].label, "ЦЬОГО ТИЖНЯ · ЩЕ 4 ДН.", "четвер")
        XCTAssertFalse(questRow(app, "daily.wakeGlass").exists, "дедлайн о 09:00")
        XCTAssertFalse(questRow(app, "daily.quarterBy").exists, "дедлайн об 11:00")
        XCTAssertFalse(app.staticTexts["home.tasks.today"].exists)
        XCTAssertFalse(app.staticTexts["home.tasks.allDailyDone"].exists)
        XCTAssertFalse(app.buttons["home.tasks.toggleCompleted"].exists, "прострочене не стає «виконаним»")
    }

    /// Несподіване (SPEC-QUESTS §9.1): картка з живим таймером над «Сьогодні»; порція закриває його — «Готово · ⚡ у
    /// призах», а ⚡ справді лежить у «Призах». Повз пікер: `--quests surprise:…`, без нього під `--uitest-*` їх немає.
    func testSurpriseCardCompletesAndGrantsBoost() {
        let app = launch(["--uitest-empty", "--quests", "surprise:surprise.glassNow@13:30",
                          "--uitest-now", "2026-10-01T13:35:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        let card = app.descendants(matching: .any)["quest.surprise"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "з'явилось о 13:30")
        XCTAssertTrue(card.isHittable, "картку видно, а не лише є в дереві")
        XCTAssertTrue(card.label.hasPrefix("Несподіване завдання: Склянка зараз"), card.label)
        XCTAssertTrue(app.staticTexts["quest.surprise.timer"].exists, "живий відлік")

        app.buttons["home.add.500"].tap()
        // «Перша крапля» й «Несподіванка» — вікно на весь екран; картка святкує після нього й згортається.
        let pages = dismissCelebrationIfPresent(app)
        XCTAssertTrue(pages.contains { $0.contains("Несподіванка") }, "\(pages)")
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "виконане — у «Виконані · N»")
        let toggle = app.buttons["home.tasks.toggleCompleted"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("Готово · ⚡ у призах"), card.label)

        app.buttons["home.level"].tap()
        let boost = app.buttons["progress.prizes.row.xp.double"]
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 10))
        for _ in 0..<6 where !(boost.exists && boost.isHittable) { app.swipeUp() }
        XCTAssertTrue(boost.isHittable, "⚡ за несподіване — у призах")
    }

    func testUndoRemovesIntakeAndRollsBackProgress() {
        let app = launch(["--uitest-empty"])
        let percent = app.staticTexts["home.percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 15))

        app.buttons["home.add.500"].tap()
        dismissCelebrationIfPresent(app)
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
        dismissCelebrationIfPresent(app)
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
        let value = app.textFields["custom.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, "300")

        app.buttons["500"].tap()
        XCTAssertEqual(value.value as? String, "500")

        app.buttons["custom.confirm"].tap()
        dismissCelebrationIfPresent(app)
        XCTAssertEqual(app.staticTexts["home.percent"].label, "25%")
    }

    /// «Інше» відкривається з останнім доданим через нього об'ємом, а не з 300 мл (WAT-45).
    func testCustomSheetOpensWithLastAmount() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        let confirm = app.buttons["custom.confirm"]
        app.buttons["home.add.custom"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        app.buttons["350"].tap()
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        dismissCelebrationIfPresent(app)

        app.buttons["home.add.custom"].tap()
        let value = app.textFields["custom.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertEqual(value.value as? String, "350")
    }

    /// Тап по числу в «Інше» — цифрова клавіатура, і точний об'єм, якого немає на сітці 50 мл (WAT-50).
    /// 314 мл — ще й пасхалка «Пі»: годинник закріплено, щоб порція не припала на повню чи 11:11.
    func testCustomSheetAcceptsExactAmountFromKeyboard() {
        let app = launch(["--uitest-empty", "--uitest-now", "2026-10-01T09:00:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        // Перша порція через «Інше» — окремо: «Перша крапля» й «Своя мірка» інакше стали б у вікні відкриття
        // поруч із пасхалкою, і першою сторінкою була б не вона.
        let confirm = app.buttons["custom.confirm"]
        app.buttons["home.add.custom"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        dismissCelebrationIfPresent(app)

        app.buttons["home.add.custom"].tap()
        let value = app.textFields["custom.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()

        // `typeText` сам падає, якщо фокуса ніде немає: тап по числу мав поставити курсор у поле.
        app.typeText("5")
        XCTAssertEqual(app.staticTexts["custom.unit"].label, "від 50 до 2000 мл")
        XCTAssertFalse(confirm.isEnabled, "поза межами порції «Додати» неактивна")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText("314")
        XCTAssertEqual(value.value as? String, "314")
        XCTAssertTrue(confirm.isEnabled)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "цифрова клавіатура")
        XCTAssertLessThanOrEqual(confirm.frame.maxY, keyboard.frame.minY,
                                 "шторка піднялася над клавіатурою, а не сховала кнопку під нею")
        XCTAssertTrue(confirm.isHittable)

        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        let found = dismissCelebrationIfPresent(app, timeout: 5)
        XCTAssertTrue(found.contains { $0.hasPrefix("Пасхалка: Пі") }, "\(found)")
        XCTAssertTrue(app.staticTexts["314 мл"].exists, "порція зʼявилась в історії")
    }

    func testGoalChangeInSettingsRecalculatesProgress() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        app.buttons["home.add.500"].tap()
        dismissCelebrationIfPresent(app)

        app.buttons["home.settings"].tap()
        let goal = app.staticTexts["settings.goal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.label, "2.0 л")

        app.buttons["settings.goal.plus"].tap()
        XCTAssertEqual(goal.label, "2.1 л", "крок — 100 мл")

        app.buttons["nav.back"].tap()
        XCTAssertEqual(app.staticTexts["home.percent"].label, "24%", "прогрес перерахований під нову норму")
    }

    // MARK: - Навігація

    func testNavigationToProgressAndAchievements() {
        let app = launch(["--uitest-demo"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 20))

        app.buttons["home.level"].tap()
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 5))

        app.buttons["progress.allAchievements"].tap()
        XCTAssertTrue(app.otherElements["achievements.counter"].waitForExistence(timeout: 5))
        XCTAssertTrue(tiles(app).firstMatch.exists)
    }

    /// Плитки сітки 2e. Сітка лінива, а досягнень 102: шукати конкретну плитку без фільтра — гадати, чи вона
    /// вже на екрані.
    private func tiles(_ app: XCUIApplication, _ predicate: String = "TRUEPREDICATE") -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'achievements.tile.' AND (\(predicate))"))
    }

    private func selectCategory(_ app: XCUIApplication, _ key: String) {
        app.buttons["achievements.category"].tap()
        let option = app.buttons["achievements.category.option.\(key)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertTrue(app.buttons["achievements.category.clear"].waitForExistence(timeout: 5))
    }

    // MARK: - Досягнення (SPEC-ACHIEVEMENTS §13)

    func testStateChipsSliceTheGridButNotTheCounter() {
        let app = launch(["--uitest-demo", "--start-screen", "achievements"])
        let counter = app.otherElements["achievements.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        let counterValue = counter.value as? String
        selectCategory(app, "streak")

        app.buttons["achievements.state.inProgress"].tap()
        XCTAssertTrue(app.buttons["achievements.tile.streak.7"].waitForExistence(timeout: 5))
        XCTAssertEqual(tiles(app, "value == 'Відкрито'").count, 0, "відкрите не «в процесі»")
        XCTAssertEqual(counter.value as? String, counterValue, "лічильник глобальний — чип його не змінює")

        app.buttons["achievements.state.unlocked"].tap()
        XCTAssertTrue(tiles(app, "value == 'Відкрито'").firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertTrue(
            tiles(app, "NOT identifier BEGINSWITH 'achievements.tile.streak.' AND NOT identifier BEGINSWITH 'achievements.tile.comeback.'")
                .firstMatch.waitForExistence(timeout: 5),
            "хрестик повертає «Всі»"
        )
    }

    /// Завдання — лише на головному (WAT-35, SPEC-QUESTS §1): на 3f блоку «ЗАВДАННЯ» немає.
    func testProgressHasNoQuestsBlock() {
        let app = launch(["--uitest-demo", "--start-screen", "progress"])
        XCTAssertTrue(app.buttons["progress.level"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["ЗАВДАННЯ"].exists)
        XCTAssertFalse(app.buttons["progress.tasks.toggleCompleted"].exists)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'quest.row.'")).firstMatch.exists)
    }

    func testBadgeOnProgressOpensTheDetailCard() {
        let app = launch(["--uitest-demo", "--start-screen", "progress"])
        XCTAssertTrue(app.staticTexts["РІВЕНЬ"].waitForExistence(timeout: 20))

        // Блок досягнень — останній на екрані, під призами. Що саме у вітрині, залежить від дати демо-історії,
        // тож беремо перший бейдж.
        let badge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'progress.achievements.badge.'")).firstMatch
        for _ in 0..<8 where !(badge.exists && badge.isHittable) { app.swipeUp() }
        XCTAssertTrue(badge.isHittable, "вітрина не порожня")
        let title = badge.label.replacingOccurrences(of: "Досягнення: ", with: "")
        badge.tap()

        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, title, "та сама картка, що й на 2e")

        app.buttons["achievements.detail.close"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 1), "хрестик закриває картку")
    }

    // MARK: - Таємні й пасхалки (SPEC-ACHIEVEMENTS-CATALOG §4.9–4.10)

    /// Таємне з підказкою — сіра плитка «???», у картці лише підказка; пасхалок у лічильнику немає.
    /// Без дозволу на сповіщення: до WAT-60 «На звʼязку» відкривалось би на старті, у фоні, і лічильник
    /// залежав би від того, чи встигло. Тепер воно зняте, але стан на старті так само не залежить від дозволу.
    func testSecretTileShowsOnlyTheHint() {
        let app = launch(["--uitest-empty", "--notifications-auth", "notDetermined", "--start-screen", "achievements"])
        let counter = app.otherElements["achievements.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        XCTAssertEqual(counter.value as? String, "0 з 102 відкрито", "пасхалки невидимі й у лічильнику")

        selectCategory(app, "stats")
        let tile = app.buttons["achievements.tile.stats.bullseye"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(tile.label, "Досягнення: ???", "справжня назва не їде в дерево доступності")
        XCTAssertEqual(tile.value as? String, "Таємне досягнення")
        tile.tap()

        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "???")
        XCTAssertEqual(card.value as? String, "«Ні краплі зайвої». Таємне досягнення", "ні умови, ні прогресу")
    }

    /// Разове досягнення — без смуги й «0/1» і на плитці, і в картці (WAT-51); багатокрокове — з прогресом.
    func testOneStepAchievementHasNoProgressBar() {
        let app = launch(["--uitest-empty", "--notifications-auth", "notDetermined", "--start-screen", "achievements"])
        XCTAssertTrue(app.otherElements["achievements.counter"].waitForExistence(timeout: 20))

        selectCategory(app, "water")
        let once = app.buttons["achievements.tile.first.drop"]
        XCTAssertTrue(once.waitForExistence(timeout: 5))
        XCTAssertEqual(once.value as? String, "Ще не відкрито")
        XCTAssertFalse(app.staticTexts["0/1"].exists, "у жодної плитки сітки")
        XCTAssertEqual(app.buttons["achievements.tile.volume.10l"].value as? String, "Прогрес 0 із 20 літрів")

        once.tap()
        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue((card.value as? String)?.hasPrefix("Перший запис води. Ще не відкрито. +") ?? false,
                      card.value as? String ?? "картка без значення")
        XCTAssertFalse(app.staticTexts["0 / 1"].exists, "і в картці — лише нагорода")
    }

    /// Об'єм — у літрах, як на кнопках порцій (WAT-52): «Відро» після склянки — «0.2/20 л», а не «250/20000».
    /// Порція — з віджета: так вона доходить і до вже відкритого екрана 2e (`epoch`), без переходів.
    func testVolumeAchievementShowsLitres() {
        let app = launch([
            "--uitest-empty", "--notifications-auth", "notDetermined", "--uitest-now", "2026-10-01T11:25:00+03:00",
            "--widget-action", "add:250", "--start-screen", "achievements"
        ])
        XCTAssertTrue(app.otherElements["achievements.counter"].waitForExistence(timeout: 20))
        // Перша порція — «Перша крапля»: вікно відкриття модальне й закриває собою екран 2e (WAT-62).
        dismissCelebrationIfPresent(app, timeout: 5)

        selectCategory(app, "water")
        let bucket = app.buttons["achievements.tile.volume.10l"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 5))
        let counted = NSPredicate(format: "value == %@", "Прогрес 0,2 із 20 літрів")
        wait(for: [expectation(for: counted, evaluatedWith: bucket)], timeout: 10)
        XCTAssertEqual(app.buttons["achievements.tile.big.gulp"].value as? String,
                       "Прогрес 250 із 1000 мілілітрів", "ціль до 1 л — мілілітри")

        bucket.tap()
        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue((card.value as? String)?.hasPrefix("20 л води загалом. Прогрес 0,2 із 20 літрів. +") ?? false,
                      card.value as? String ?? "картка без значення")
    }

    /// Пасхалка: до знахідки її не видно, знахідка — своє вікно з підписом «Пасхалка», а потім «🥚 1» поруч із
    /// лічильником і рядок «Пасхалка! Тут їх більше» в картці. «Дискотека» — п'ять змін теми за хвилину.
    func testEasterEggIsFoundWithItsOwnWindow() {
        let app = launch(["--uitest-empty", "--notifications-auth", "notDetermined", "--start-screen", "settings"])
        let theme = app.buttons["settings.theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 20))
        // Після картки «Одиниці» (WAT-58) рядок теми — нижче краю екрана: докручуємо один раз заздалегідь.
        app.swipeUp()
        XCTAssertTrue(theme.isHittable)
        // Перша зміна на темну — «Темна сторона»: вікно поверх налаштувань, закрити й перемикати далі.
        theme.tap()
        XCTAssertTrue(dismissCelebrationIfPresent(app).first?.contains("Темна сторона") ?? false)
        for _ in 0..<4 { theme.tap() }

        let found = dismissCelebrationIfPresent(app, timeout: 5)
        XCTAssertTrue(found.first?.hasPrefix("Пасхалка: Дискотека") ?? false, "\(found)")

        app.buttons["nav.back"].firstMatch.tap()
        app.buttons["home.level"].tap()
        let all = app.buttons["progress.allAchievements"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()

        let counter = app.otherElements["achievements.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.value as? String, "1 з 102 відкрито, пасхалок знайдено: 1",
                       "«Темна сторона» — у лічильнику, пасхалка — окремо")
        let tile = app.buttons["achievements.tile.egg.disco"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        let card = app.otherElements["achievements.detail"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "Дискотека")
        XCTAssertTrue((card.value as? String)?.contains("Пасхалка! Тут їх більше") ?? false)
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

        // Результат видно в самій картці: кнопка стала плашкою підтвердження.
        let success = app.descendants(matching: .any)["prizes.detail.success"]
        XCTAssertTrue(success.waitForExistence(timeout: 2), "після дії картка показує підтвердження")
        XCTAssertTrue(success.isHittable, "підтвердження видно, а не просто є в дереві")
        XCTAssertTrue(success.label.contains("Серію збережено"))
        XCTAssertFalse(action.exists, "кнопки під час підтвердження немає — другий тап нічого не витратить")
        let card = app.otherElements["prizes.detail"]
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        wait(for: [closed], timeout: 5)

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
        let card = app.otherElements["prizes.detail"]
        // Картка центрована по вертикалі: зміна її висоти зсунула б хрестик у кутку.
        // Рамку самого блоку не міряємо — кільце успіху навколо іконки розширює її, не
        // змінюючи розкладки.
        let close = app.buttons["prizes.detail.close"]
        let closeY = close.frame.minY
        let buttonFrame = action.frame
        action.tap()

        let success = app.descendants(matching: .any)["prizes.detail.success"]
        XCTAssertTrue(success.waitForExistence(timeout: 2))
        XCTAssertTrue(success.label.hasPrefix("Увімкнено до"), success.label)
        // Картка не змінює висоту: плашка стає на місце кнопки, опис — поверх прихованого вмісту.
        XCTAssertEqual(close.frame.minY, closeY, accuracy: 0.5, "висота картки не змінилась")
        XCTAssertEqual(success.frame.height, buttonFrame.height, accuracy: 0.5, "плашка тієї ж висоти, що кнопка")
        XCTAssertEqual(success.frame.minY, buttonFrame.minY, accuracy: 0.5, "плашка на місці кнопки")
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)], timeout: 5)

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

    /// Налаштування — екран у стеку (WAT-15): «Сповіщення» відкриваються поверх нього,
    /// «назад» вертає в налаштування, ще раз — на головний.
    func testSettingsIsFullScreenInNavigationStack() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.settings"].tap()
        let row = app.buttons["settings.notifications"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let percent = app.staticTexts["home.percent"]
        XCTAssertFalse(percent.exists && percent.isHittable, "головного під налаштуваннями не видно")

        row.tap()
        XCTAssertTrue(app.buttons["notifications.master"].waitForExistence(timeout: 5))
        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "назад — у налаштування, а не на головний")
        XCTAssertTrue(row.isHittable)

        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home.percent"].isHittable)
    }

    /// «Кнопки порцій» (WAT-45): змінена кнопка з'являється на головному, підказка — у шторці «Інше».
    func testPortionButtonsReachHomeAndCustomSheet() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.settings"].tap()
        let row = app.buttons["settings.portions"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let first = app.staticTexts["portions.home.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["portions.home.reset"].exists, "типові — повертати нічого")
        app.buttons["portions.home.0.plus"].tap()
        // «Свої кнопки» — вікном поверх екрана (WAT-60).
        dismissCelebrationIfPresent(app)
        XCTAssertEqual(first.label, "250 мл")
        // До 1 л — мілілітри по 50, від 1 л — літри по 100 мл; кожен тап змінює підпис.
        let second = app.staticTexts["portions.home.1"]
        XCTAssertEqual(second.label, "500 мл")
        app.buttons["portions.home.1.plus"].tap()
        XCTAssertEqual(second.label, "550 мл")
        app.buttons["portions.home.1.minus"].tap()
        XCTAssertEqual(app.staticTexts["portions.home.2"].label, "1 л")
        app.buttons["portions.home.2.plus"].tap()
        XCTAssertEqual(app.staticTexts["portions.home.2"].label, "1.1 л", "від 1 л — крок 100 мл")
        app.buttons["portions.home.2.minus"].tap()
        app.buttons["portions.custom.3.plus"].tap()
        XCTAssertEqual(app.staticTexts["portions.custom.3"].label, "550 мл")
        XCTAssertTrue(app.buttons["portions.home.reset"].exists)

        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label.contains("250 мл"), true, "підпис рядка — нові кнопки")
        app.buttons["nav.back"].firstMatch.tap()

        XCTAssertTrue(app.buttons["home.add.250"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.add.200"].exists)
        app.buttons["home.add.custom"].tap()
        XCTAssertTrue(app.buttons["550"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["500"].exists)
    }

    /// Системи об'єму (WAT-46): «Унції» переводять кнопки, кільце й мету в унції; «Мілілітри» — повертають як було.
    func testVolumeUnitSwitchesToOuncesAndBack() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.settings"].tap()
        // Секція «Одиниці» (WAT-58): сегменти — `WTSegmentRow`, ідентифікатор на кожному.
        let ounces = app.buttons["settings.units.volume.1"]
        XCTAssertTrue(ounces.waitForExistence(timeout: 5))
        XCTAssertEqual(ounces.label, "Унції")
        ounces.tap()
        XCTAssertTrue(ounces.isSelected)
        XCTAssertEqual(app.staticTexts["settings.goal"].label, "68 унц.")
        XCTAssertTrue(app.buttons["settings.portions"].label.contains("8 · 16 · 32 унц."))
        app.buttons["nav.back"].firstMatch.tap()

        let cup = app.buttons["home.add.237"]
        XCTAssertTrue(cup.waitForExistence(timeout: 5))
        XCTAssertEqual(cup.label, "8 унц.")
        cup.tap()
        dismissCelebrationIfPresent(app)
        XCTAssertEqual(app.staticTexts["home.volume"].label, "8 / 68 унц.")

        app.buttons["home.settings"].tap()
        let milliliters = app.buttons["settings.units.volume.0"]
        XCTAssertTrue(milliliters.waitForExistence(timeout: 5))
        milliliters.tap()
        XCTAssertEqual(app.staticTexts["settings.goal"].label, "2.0 л")
        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home.add.200"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home.volume"].label, "0.24 / 2.0 л")
    }

    /// Формат часу й вага в «Налаштуваннях» (WAT-58): «12 годин» одразу міняє годинник капсули й історії
    /// на головному та час на екрані «Сповіщення»; «24 години» повертає як було. Годинник — 11:25, як у
    /// тесті капсули: частина доби триває, і дедлайн — полудень.
    func testUnitsSectionSwitchesTimeFormatAndMass() {
        let app = launch(["--uitest-empty", "--uitest-now", "2026-10-01T11:25:00+03:00"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))
        let pill = app.descendants(matching: .any)["home.dayPart"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "До 12:00 бракує 700 мл, лишилось 35 хвилин")

        app.buttons["home.settings"].tap()
        let twelveHours = app.buttons["settings.units.time.1"]
        XCTAssertTrue(twelveHours.waitForExistence(timeout: 5))
        XCTAssertEqual(twelveHours.label, "12 годин")
        XCTAssertTrue(app.buttons["settings.units.time.0"].isSelected, "типово — 24 години")
        twelveHours.tap()
        XCTAssertTrue(twelveHours.isSelected)
        let pounds = app.buttons["settings.units.mass.1"]
        XCTAssertEqual(pounds.label, "Фунти")
        pounds.tap()
        XCTAssertTrue(pounds.isSelected)
        XCTAssertFalse(app.buttons["settings.units.mass.0"].isSelected)
        app.buttons["nav.back"].firstMatch.tap()

        XCTAssertEqual(pill.label, "До 12:00 пп бракує 700 мл, лишилось 35 хвилин")
        app.buttons["home.add.200"].tap()
        dismissCelebrationIfPresent(app)
        XCTAssertTrue(app.staticTexts["11:25 дп"].waitForExistence(timeout: 5), "час порції в історії")

        app.buttons["home.settings"].tap()
        let notifications = app.buttons["settings.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
        let wake = app.staticTexts["notifications.wake"]
        XCTAssertTrue(wake.waitForExistence(timeout: 5))
        XCTAssertEqual(wake.label, "8:00 дп")
        XCTAssertEqual(app.staticTexts["notifications.sleep"].label, "10:00 пп")
        app.buttons["nav.back"].firstMatch.tap()

        let twentyFour = app.buttons["settings.units.time.0"]
        XCTAssertTrue(twentyFour.waitForExistence(timeout: 5))
        twentyFour.tap()
        app.buttons["nav.back"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["11:25"].waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "До 12:00 бракує 500 мл, лишилось 35 хвилин")
    }

    // MARK: - Тема

    func testDarkThemeToggle() {
        let app = launch(["--uitest-empty"])
        XCTAssertTrue(app.staticTexts["home.percent"].waitForExistence(timeout: 15))

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.staticTexts["Темна тема"].waitForExistence(timeout: 5))
        app.buttons["settings.theme"].tap()
        // «Темна сторона» — вікном поверх налаштувань (WAT-60).
        dismissCelebrationIfPresent(app)
        app.buttons["nav.back"].tap()

        XCTAssertTrue(app.staticTexts["home.percent"].exists, "екран лишається робочим у темній темі")
    }
}
