import XCTest
import Core
@testable import Widgets

/// Стан доби на хвилину запису — ті самі блоки й цілі, що в капсули, чекпоінта й XP.
final class WidgetDayTests: XCTestCase {
    func testBlocksAndCurrentPartMatchCore() {
        let day = WidgetDay.resolve(Fixture.snapshot(), at: Fixture.date(13, 25), calendar: Fixture.calendar)

        XCTAssertEqual(day.blocks.map(\.goal.targetMl), [689, 826, 485])
        XCTAssertEqual(day.blocks.map(\.drunkMl), [800, 200, 0])
        XCTAssertEqual(day.blocks.map(\.position), [.past, .current, .future])
        XCTAssertEqual(day.part?.block.toMinute, 17 * 60)
        XCTAssertEqual(day.part?.leftMl, 626)
        XCTAssertEqual(day.phase, .active)
        XCTAssertEqual(day.percent, 50)
        XCTAssertFalse(day.isProjected)
    }

    /// 1000 мл о 13:25 проти E = 923 — попереду на 77 мл.
    func testPaceDelta() {
        let day = WidgetDay.resolve(Fixture.snapshot(), at: Fixture.date(13, 25), calendar: Fixture.calendar)
        XCTAssertEqual(day.expectedMl, 923)
        XCTAssertEqual(day.paceDeltaMl, 77)
    }

    func testPaceDeltaHiddenWithoutDayRhythm() {
        let day = WidgetDay.resolve(Fixture.snapshot(rhythm: false), at: Fixture.date(13, 25), calendar: Fixture.calendar)
        XCTAssertNil(day.paceDeltaMl)
    }

    func testPhases() {
        let snapshot = Fixture.snapshot()
        XCTAssertEqual(WidgetDay.resolve(snapshot, at: Fixture.date(7, 0), calendar: Fixture.calendar).phase, .beforeWake)
        XCTAssertEqual(WidgetDay.resolve(snapshot, at: Fixture.date(22, 30), calendar: Fixture.calendar).phase, .afterSleep)
        XCTAssertNil(WidgetDay.resolve(snapshot, at: Fixture.date(22, 30), calendar: Fixture.calendar).part)
    }

    /// Нова доба без запуску застосунку: 0 мл, та сама норма, серія — лише якщо вчора закрито.
    func testNextDayIsProjected() {
        let closed = Fixture.snapshot(streak: .init(current: 12, countsToday: true))
        let tomorrow = Fixture.date(9, 0, day: 9)
        let day = WidgetDay.resolve(closed, at: tomorrow, calendar: Fixture.calendar)

        XCTAssertTrue(day.isProjected)
        XCTAssertEqual(day.countedMl, 0)
        XCTAssertEqual(day.goalMl, 2000)
        XCTAssertEqual(day.streak, 12)
        XCTAssertFalse(day.questsAreCurrent)
        XCTAssertNil(day.reserve)

        let open = Fixture.snapshot(streak: .init(current: 12, countsToday: false))
        XCTAssertNil(WidgetDay.resolve(open, at: tomorrow, calendar: Fixture.calendar).streak)
        XCTAssertNil(WidgetDay.resolve(closed, at: Fixture.date(9, 0, day: 10), calendar: Fixture.calendar).streak)
    }

    /// 10 жовтня 2026 — субота: спроєктована доба бере розклад вихідних.
    func testProjectedWeekendUsesWeekendSchedule() {
        let day = WidgetDay.resolve(Fixture.snapshot(), at: Fixture.date(9, 0, day: 10), calendar: Fixture.calendar)
        XCTAssertEqual(day.schedule.wakeMinutes, 10 * 60)
        XCTAssertEqual(day.phase, .beforeWake)
    }

    func testUndoWindow() {
        let action = WidgetSnapshot.LastAction(intakeId: Fixture.uuid(4), ml: 200, at: Fixture.date(12, 50))
        let snapshot = Fixture.snapshot(lastAction: action)
        XCTAssertEqual(WidgetDay.resolve(snapshot, at: Fixture.date(12, 50), calendar: Fixture.calendar).undo, action)
        XCTAssertNil(WidgetDay.resolve(snapshot, at: Fixture.date(12, 51), calendar: Fixture.calendar).undo)

        // Порцію вже видалили в застосунку — скасовувати нічого.
        let gone = Fixture.snapshot(portions: Array(Fixture.aheadPortions.dropLast()), lastAction: action)
        XCTAssertNil(WidgetDay.resolve(gone, at: Fixture.date(12, 50), calendar: Fixture.calendar).undo)
    }
}
