import XCTest
@testable import Core

final class ReportPeriodTests: XCTestCase {
    private let calendar = CalendarService(clock: FixedClock(now: Date(timeIntervalSince1970: 1_791_100_000)))

    func testEncodingRoundTrip() {
        let periods: [ReportPeriod] = [.day(DayKey(rawValue: "2026-10-04")),
                                       .week(start: DayKey(rawValue: "2026-09-21")),
                                       .month(MonthKey(rawValue: "2026-09"))]
        for period in periods {
            XCTAssertEqual(ReportPeriod(encoded: period.encoded), period)
        }
        XCTAssertNil(ReportPeriod(encoded: "year:2026"))
        XCTAssertNil(ReportPeriod(encoded: "week"))
    }

    /// 4 жовтня 2026 — неділя; тиждень починається з понеділка 28 вересня.
    func testWeekStartsOnMonday() {
        let sunday = DayKey(rawValue: "2026-10-04")
        XCTAssertEqual(calendar.weekdayIndex(of: sunday), 6)
        XCTAssertTrue(calendar.isWeekend(sunday))
        XCTAssertEqual(calendar.period(.week, containing: sunday), .week(start: DayKey(rawValue: "2026-09-28")))
        XCTAssertEqual(calendar.weekdayIndex(of: DayKey(rawValue: "2026-09-28")), 0)
    }

    func testDaysInPeriod() {
        let week = calendar.days(in: .week(start: DayKey(rawValue: "2026-09-28")))
        XCTAssertEqual(week.first?.rawValue, "2026-09-28")
        XCTAssertEqual(week.last?.rawValue, "2026-10-04")
        let february = calendar.days(in: .month(MonthKey(rawValue: "2026-02")))
        XCTAssertEqual(february.count, 28)
        XCTAssertEqual(february.last?.rawValue, "2026-02-28")
    }

    func testShift() {
        XCTAssertEqual(calendar.shifted(.week(start: DayKey(rawValue: "2026-09-28")), by: -1),
                       .week(start: DayKey(rawValue: "2026-09-21")))
        XCTAssertEqual(calendar.shifted(.month(MonthKey(rawValue: "2026-01")), by: -1),
                       .month(MonthKey(rawValue: "2025-12")))
        XCTAssertEqual(calendar.shifted(.day(DayKey(rawValue: "2026-03-01")), by: -1),
                       .day(DayKey(rawValue: "2026-02-28")))
    }
}
