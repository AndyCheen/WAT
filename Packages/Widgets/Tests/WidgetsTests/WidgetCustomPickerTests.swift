import XCTest
@testable import Widgets

/// Вибір «Інше» у віджеті (рішення від 09.10.2026): розгортається окремо для кожного віджета й сам згортається.
final class WidgetCustomPickerTests: XCTestCase {
    private func picker() -> WidgetCustomPicker {
        WidgetCustomPicker(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testOpensPerWidgetAndClosesAfterAMinute() {
        let picker = picker()
        let opened = Fixture.date(13, 0)
        picker.open(.quickAdd, at: opened)

        XCTAssertTrue(picker.isOpen(.quickAdd, at: opened.addingTimeInterval(30)))
        XCTAssertFalse(picker.isOpen(.overview, at: opened.addingTimeInterval(30)), "інший віджет не розгортається")
        XCTAssertEqual(picker.closesAt(.quickAdd, now: opened), opened.addingTimeInterval(WidgetCustomPicker.window))
        XCTAssertFalse(picker.isOpen(.quickAdd, at: opened.addingTimeInterval(61)))
        XCTAssertNil(picker.closesAt(.quickAdd, now: opened.addingTimeInterval(61)))
    }

    func testCloseAndCloseAll() {
        let picker = picker()
        let now = Fixture.date(13, 0)
        picker.open(.quickAdd, at: now)
        picker.open(.reserve, at: now)
        picker.close(.quickAdd)
        XCTAssertFalse(picker.isOpen(.quickAdd, at: now))
        XCTAssertTrue(picker.isOpen(.reserve, at: now))
        picker.closeAll()
        XCTAssertFalse(picker.isOpen(.reserve, at: now))
    }

    /// Віджет згортається сам: у таймлайні є запис на мить згортання.
    func testTimelineHasEntryWhenPickerCloses() {
        let now = Fixture.date(13, 25)
        let closes = now.addingTimeInterval(60)
        let dates = WidgetTimeline.dates(for: .quickAdd, snapshot: Fixture.snapshot(), from: now,
                                         calendar: Fixture.calendar, pickerClosesAt: closes)
        XCTAssertTrue(dates.contains(closes))
    }

    func testHintsFallBackToDefaults() {
        var snapshot = Fixture.snapshot()
        XCTAssertEqual(snapshot.hints, WidgetSnapshot.defaultCustomHints)
        snapshot.customHints = [300, 300, 700, 1200]
        XCTAssertEqual(snapshot.hints, [300, 300, 700, 1200], "дублі дозволені, як у WAT-45")
    }

    /// Поки «Скасувати» на екрані, підказки не видно: щойно додана порція важливіша.
    func testUndoHidesPicker() {
        let action = WidgetSnapshot.LastAction(intakeId: Fixture.uuid(4), ml: 200, at: Fixture.date(12, 50))
        let content = WidgetContent(snapshot: Fixture.snapshot(lastAction: action), at: Fixture.date(12, 50),
                                    calendar: Fixture.calendar, customPickerOpen: true)
        XCTAssertFalse(content.showsCustomPicker)
        let calm = WidgetContent(snapshot: Fixture.snapshot(), at: Fixture.date(13, 0), calendar: Fixture.calendar,
                                 customPickerOpen: true)
        XCTAssertTrue(calm.showsCustomPicker)
    }
}
