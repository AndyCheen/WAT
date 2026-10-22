import XCTest

/// Вікно відкриття досягнень (WAT-60, SPEC-ACHIEVEMENTS §8) — на весь екран і модальне: поки воно відкрите,
/// решта екрана для XCUITest не досяжна. Сценарій, що додає першу порцію чи робить «Відкриття», закриває його,
/// як людина, — «Далі» / «Чудово», поки вікно є.
///
/// - Parameter timeout: скільки чекати появи. Вікно з'являється не одразу: після дії на головному — коли догра
///   кільце (≈ 0,6 с), і перші 0,5 с кнопка тап ігнорує, тож тапаємо, поки вікно не зникне.
/// - Returns: назви сторінок закритого вікна — для перевірок у сценарії.
@discardableResult
func dismissCelebrationIfPresent(_ app: XCUIApplication, timeout: TimeInterval = 3,
                                 file: StaticString = #filePath, line: UInt = #line) -> [String] {
    let primary = app.buttons["celebration.primary"]
    guard primary.waitForExistence(timeout: timeout) else { return [] }
    var titles: [String] = []
    let deadline = Date().addingTimeInterval(15)
    while primary.exists, Date() < deadline {
        let title = app.staticTexts["celebration.title"]
        if title.exists, titles.last != title.label { titles.append(title.label) }
        primary.tap()
        // Сторінка змінюється з анімацією, а кнопка після появи пів секунди «спить».
        _ = primary.waitForNonExistence(timeout: 0.7)
    }
    XCTAssertFalse(primary.exists, "вікно відкриття не закрилося", file: file, line: line)
    return titles
}
