import XCTest
@testable import Core

/// Номер доби без `Calendar` (WAT-24): правила досягнень ходять історією днями.
final class DayKeyOrdinalTests: XCTestCase {
    func testEpochAndRoundTrip() {
        XCTAssertEqual(DayKey(rawValue: "1970-01-01").ordinal, 0)
        XCTAssertEqual(DayKey(rawValue: "2026-10-15").ordinal - DayKey(rawValue: "2026-09-30").ordinal, 15)
        for raw in ["2024-02-29", "2026-12-31", "2027-01-01", "2000-03-01", "2100-02-28"] {
            XCTAssertEqual(DayKey(ordinal: DayKey(rawValue: raw).ordinal).rawValue, raw)
        }
    }

    func testMatchesFoundationCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2023, month: 1, day: 1))!
        for offset in stride(from: 0, to: 1500, by: 7) {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = DayKey(date: date, calendar: calendar)
            XCTAssertEqual(key.ordinal, Int(date.timeIntervalSince1970 / 86_400), key.rawValue)
            // Calendar: неділя = 1 … субота = 7; тут понеділок = 0.
            XCTAssertEqual(key.weekdayIndex, (calendar.component(.weekday, from: date) + 5) % 7, key.rawValue)
        }
    }

    func testLeapYearsAndMonthLengths() {
        XCTAssertTrue(DayKey.isLeapYear(2028))
        XCTAssertFalse(DayKey.isLeapYear(2100))
        XCTAssertTrue(DayKey.isLeapYear(2000))
        XCTAssertEqual(DayKey.daysIn(year: 2028, month: 2), 29)
        XCTAssertEqual(DayKey.daysIn(year: 2026, month: 2), 28)
        XCTAssertEqual(DayKey.daysIn(year: 2026, month: 9), 30)
        XCTAssertEqual(DayKey.daysIn(year: 2026, month: 12), 31)
    }
}
