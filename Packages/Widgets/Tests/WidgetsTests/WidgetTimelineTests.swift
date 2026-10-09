import XCTest
import Core
@testable import Widgets

final class WidgetTimelineTests: XCTestCase {
    private func reserve() -> HydrationReserve? {
        HydrationReserve.make(portions: Fixture.aheadPortions, capacityMl: 500, now: Fixture.date(13, 25),
                              plannedReminder: nil, previous: nil, zero: Fixture.paceZero())
    }

    func testKeyMomentsWithoutCadence() {
        let snapshot = Fixture.snapshot(reserve: reserve())
        let dates = WidgetTimeline.dates(for: .today, snapshot: snapshot, from: Fixture.date(13, 25), calendar: Fixture.calendar)

        XCTAssertEqual(dates.first, Fixture.date(13, 25))
        XCTAssertTrue(dates.contains(Fixture.date(17, 0)), "кінець блоку")
        XCTAssertTrue(dates.contains(Fixture.date(15, 14)), "нуль запасу")
        XCTAssertFalse(dates.contains(Fixture.date(13, 30)), "без кроку")
        XCTAssertTrue(dates.allSatisfy { $0 <= Fixture.date(19, 25) }, "горизонт 6 год")
    }

    /// Крапля — кроком 5 хв, але лише до нуля: далі вона порожня, і таймлайн тягнеться ключовими моментами.
    func testReserveStepsStopAtZero() {
        let snapshot = Fixture.snapshot(reserve: reserve())
        let dates = WidgetTimeline.dates(for: .reserve, snapshot: snapshot, from: Fixture.date(14, 30), calendar: Fixture.calendar)
        XCTAssertTrue(dates.contains(Fixture.date(14, 35)))
        XCTAssertTrue(dates.contains(Fixture.date(15, 10)))
        XCTAssertTrue(dates.contains(Fixture.date(15, 14)), "нуль запасу")
        XCTAssertFalse(dates.contains(Fixture.date(15, 20)))
        XCTAssertTrue(dates.contains(Fixture.date(17, 0)))
        XCTAssertEqual(dates, dates.sorted())
    }

    /// Кроків, що не вміщаються в 12, таймлайн не тягне — закінчується на 12-му, і WidgetKit просить новий:
    /// інакше після тапу віджет чекав би, поки намалюються всі записи на 6 год уперед.
    func testCadenceWindowEndsTimeline() {
        let snapshot = Fixture.snapshot(reserve: reserve())
        let reserve = WidgetTimeline.dates(for: .reserve, snapshot: snapshot, from: Fixture.date(13, 25), calendar: Fixture.calendar)
        XCTAssertEqual(reserve.count, 13)
        XCTAssertEqual(reserve.last, Fixture.date(14, 25))

        let rhythm = WidgetTimeline.dates(for: .rhythm, snapshot: snapshot, from: Fixture.date(13, 25), calendar: Fixture.calendar)
        XCTAssertEqual(rhythm.last, Fixture.date(16, 25), "крок 15 хв — 3 год")
        XCTAssertFalse(rhythm.contains(Fixture.date(17, 0)), "кінець блоку — уже в наступному таймлайні")
        XCTAssertLessThanOrEqual(rhythm.count, WidgetTimeline.maxEntries)
    }

    func testMidnight() {
        let dates = WidgetTimeline.dates(for: .button, snapshot: Fixture.snapshot(), from: Fixture.date(21, 0), calendar: Fixture.calendar)
        XCTAssertTrue(dates.contains(Fixture.date(0, 0, day: 9)))
    }

    /// Поки видно «Скасувати», таймлайн — до його кінця: після тапу WidgetKit малює два записи, а не дюжину.
    func testUndoPanelEndsTimeline() throws {
        let portion = try XCTUnwrap(Fixture.aheadPortions.last)
        let action = WidgetSnapshot.LastAction(intakeId: portion.id, ml: portion.ml, at: portion.at)
        let snapshot = Fixture.snapshot(reserve: reserve(), lastAction: action)
        let dates = WidgetTimeline.dates(for: .reserve, snapshot: snapshot, from: portion.at, calendar: Fixture.calendar)
        XCTAssertEqual(dates, [portion.at, portion.at.addingTimeInterval(WidgetSnapshot.undoWindow)])

        // Панель зникла — звичайний таймлайн.
        let later = portion.at.addingTimeInterval(WidgetSnapshot.undoWindow)
        XCTAssertGreaterThan(WidgetTimeline.dates(for: .reserve, snapshot: snapshot, from: later, calendar: Fixture.calendar).count, 2)
    }

    func testCustomPickerEndsTimeline() {
        let closes = Fixture.date(13, 26)
        let dates = WidgetTimeline.dates(for: .quickAdd, snapshot: Fixture.snapshot(), from: Fixture.date(13, 25),
                                         calendar: Fixture.calendar, pickerClosesAt: closes)
        XCTAssertEqual(dates, [Fixture.date(13, 25), closes])
    }

    func testNoSnapshotStillRefreshesAtMidnight() {
        let dates = WidgetTimeline.dates(for: .today, snapshot: nil, from: Fixture.date(21, 0), calendar: Fixture.calendar)
        XCTAssertEqual(dates, [Fixture.date(21, 0), Fixture.date(0, 0, day: 9)])
    }

    func testRelevance() {
        let calendar = Fixture.calendar
        let snapshot = Fixture.snapshot(reserve: reserve())
        XCTAssertEqual(WidgetTimeline.relevance(WidgetDay.resolve(snapshot, at: Fixture.date(13, 25), calendar: calendar)), 0.1)
        XCTAssertEqual(WidgetTimeline.relevance(WidgetDay.resolve(snapshot, at: Fixture.date(15, 30), calendar: calendar)), 1)
        XCTAssertEqual(WidgetTimeline.relevance(WidgetDay.resolve(snapshot, at: Fixture.date(23, 0), calendar: calendar)), 0)

        // Без запасу: частина доби спливає за 45 хв — 0,8; вечір без норми — 0,6.
        let plain = Fixture.snapshot()
        XCTAssertEqual(WidgetTimeline.relevance(WidgetDay.resolve(plain, at: Fixture.date(16, 30), calendar: calendar)), 0.8)
        XCTAssertEqual(WidgetTimeline.relevance(WidgetDay.resolve(plain, at: Fixture.date(19, 30), calendar: calendar)), 0.6)
    }
}
