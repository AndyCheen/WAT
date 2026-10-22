import XCTest

/// Розділ «Знання» (WAT-53, SPEC-LEARN): вхід із шапки, гортання до фінішу, вікторина з переворотом,
/// контекстний вхід із довідника «Звідки XP».
final class LearnUITests: XCTestCase {

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

    /// Тап по правій третині — наступний слайд, як у звіті-історії.
    private func tapNext(_ app: XCUIApplication) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
    }

    func testStoryFromHomeIsReadToTheFinishAndMarkedRead() {
        let app = launch(["--uitest-empty"])
        let entry = app.buttons["home.learn"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()

        let story = app.buttons["learn.story.app.xp"]
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        for _ in 0..<3 where !story.isHittable { app.scrollViews["learn.screen"].swipeUp() }
        story.tap()

        let finish = app.staticTexts["learn.finish"]
        for _ in 0..<10 where !finish.exists { tapNext(app) }
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.isHittable)

        app.buttons["learn.done"].tap()
        // «Цікавинка» — вікном уже після історії (WAT-60).
        XCTAssertTrue(dismissCelebrationIfPresent(app).first?.contains("Цікавинка") ?? false)
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        XCTAssertTrue(story.label.contains("прочитано"), "обкладинка дочитаної — з ✓: \(story.label)")
    }

    func testQuizCardFlipsToTheAnswer() {
        let app = launch(["--uitest-empty", "--start-screen", "learn:body.why:4"])
        let myth = app.buttons["learn.quiz.myth"]
        XCTAssertTrue(myth.waitForExistence(timeout: 15))
        myth.tap()

        let result = app.staticTexts["learn.quiz.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        XCTAssertTrue(result.isHittable, "зворот картки на екрані, а не за ним")
        XCTAssertEqual(result.label, "✓ Правильно")
        XCTAssertFalse(myth.isHittable, "лицьовий бік сховано — вдруге не відповісти")
    }

    func testXpGuideLeadsToTheStory() {
        let app = launch(["--uitest-demo", "--start-screen", "level-road"])
        let guide = app.buttons["levelRoad.guideButton"]
        XCTAssertTrue(guide.waitForExistence(timeout: 20))
        guide.tap()

        let more = app.buttons["levelRoad.guide.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        XCTAssertTrue(app.buttons["learn.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["XP і рівні"].exists, "відкрито саме історію «XP і рівні»")
    }
}
