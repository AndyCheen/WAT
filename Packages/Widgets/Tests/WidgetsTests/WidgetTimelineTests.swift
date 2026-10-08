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

    /// Крапля — кроком 5 хв, але лише до нуля: далі вона порожня.
    func testReserveStepsStopAtZero() {
        let snapshot = Fixture.snapshot(reserve: reserve())
        let dates = WidgetTimeline.dates(for: .reserve, snapshot: snapshot, from: Fixture.date(13, 25), calendar: Fixture.calendar)
        XCTAssertTrue(dates.contains(Fixture.date(13, 30)))
        XCTAssertTrue(dates.contains(Fixture.date(15, 10)))
        XCTAssertFalse(dates.contains(Fixture.date(15, 20)))
        XCTAssertTrue(dates.contains(Fixture.date(17, 0)))
        XCTAssertLessThanOrEqual(dates.count, WidgetTimeline.maxEntries)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testMidnightAndUndoExpiry() {
        let action = WidgetSnapshot.LastAction(intakeId: Fixture.uuid(4), ml: 200, at: Fixture.date(21, 0))
        let snapshot = Fixture.snapshot(lastAction: action)
        let dates = WidgetTimeline.dates(for: .button, snapshot: snapshot, from: Fixture.date(21, 0), calendar: Fixture.calendar)
        XCTAssertTrue(dates.contains(Fixture.date(21, 1)))
        XCTAssertTrue(dates.contains(Fixture.date(0, 0, day: 9)))
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
