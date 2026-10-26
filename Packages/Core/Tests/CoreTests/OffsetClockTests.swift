import XCTest
@testable import Core

/// Годинник режиму розробника (WAT-68) і мить дня за хвилиною — обидва потрібні, щоб порція «о 08:32» минулого дня
/// лягла саме на 08:32.
final class OffsetClockTests: XCTestCase {
    private let kyiv = TimeZone(identifier: "Europe/Kyiv")!

    func testOffsetMovesTimeAndCanChangeOnTheFly() {
        let base = FixedClock(now: Date(timeIntervalSince1970: 1_790_000_000), timeZone: kyiv)
        let clock = OffsetClock(base: base, offset: 3600)
        XCTAssertEqual(clock.now, base.now.addingTimeInterval(3600))

        clock.offset = -86_400
        XCTAssertEqual(clock.now, base.now.addingTimeInterval(-86_400))
        XCTAssertEqual(clock.timeZone, kyiv)
    }

    func testMinuteOfDayRoundTripsOnClockChangeDay() {
        let calendar = CalendarService(clock: FixedClock(now: Date(timeIntervalSince1970: 1_790_000_000), timeZone: kyiv))
        // 25.10.2026 — перехід на зимовий час: «північ + 512 хв» — це 07:32, а не 08:32.
        let day = DayKey(rawValue: "2026-10-25")
        let moment = calendar.date(day, minute: 8 * 60 + 32)

        XCTAssertEqual(calendar.minuteOfDay(moment), 8 * 60 + 32)
        XCTAssertEqual(calendar.dayKey(for: moment), day)
    }
}
