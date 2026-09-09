import XCTest
@testable import Core

final class CalendarServiceTests: XCTestCase {
    /// 18 липня 2026, 14:30 за Києвом — референсна точка всіх фікстур (PLAN.md §6).
    private func makeService(hour: Int = 14) -> CalendarService {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18; c.hour = hour; c.minute = 30
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let date = cal.date(from: c)!
        return CalendarService(clock: FixedClock(now: date))
    }

    func testTodayKey() {
        XCTAssertEqual(makeService().today.rawValue, "2026-07-18")
    }

    func testMonthTitleIsUkrainian() {
        let s = makeService()
        XCTAssertEqual(s.monthTitle(s.currentMonth), "Липень 2026")
    }

    func testRecentDaysAreOrderedOldestFirst() {
        let days = makeService().recentDays(7).map(\.rawValue)
        XCTAssertEqual(days.first, "2026-07-12")
        XCTAssertEqual(days.last, "2026-07-18")
        XCTAssertEqual(days.count, 7)
    }

    /// WAT-11: тиждень фіксований (Пн ліворуч), а не ковзне вікно з «сьогодні» праворуч.
    func testWeekDaysStartOnMondayAndEndOnSunday() {
        // 18 липня 2026 — субота, тож тиждень це 13.07 (Пн) … 19.07 (Нд).
        let days = makeService().weekDays().map(\.rawValue)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, "2026-07-13")
        XCTAssertEqual(days.last, "2026-07-19")
        XCTAssertEqual(days[5], "2026-07-18", "сьогодні — 6-та позиція, а не крайня права")
    }

    func testWeekDaysCrossYearBoundary() {
        // 1 січня 2026 — четвер, тиждень починається торік.
        let days = makeService().weekDays(containing: DayKey(rawValue: "2026-01-01")).map(\.rawValue)
        XCTAssertEqual(days.first, "2025-12-29")
        XCTAssertEqual(days.last, "2026-01-04")
    }

    func testMonthGridStartsOnMonday() {
        let s = makeService()
        // 1 липня 2026 — середа, отже дві порожні комірки (Пн, Вт).
        XCTAssertEqual(s.leadingBlanks(in: MonthKey(year: 2026, month: 7)), 2)
        XCTAssertEqual(s.numberOfDays(in: MonthKey(year: 2026, month: 7)), 31)
    }

    func testMonthNavigationCrossesYearBoundary() {
        let s = makeService()
        XCTAssertEqual(s.monthKey(offsetMonths: -7, from: MonthKey(year: 2026, month: 7)).rawValue, "2025-12")
        XCTAssertEqual(s.monthKey(offsetMonths: 6, from: MonthKey(year: 2026, month: 7)).rawValue, "2027-01")
    }

    func testDaysBetween() {
        let s = makeService()
        XCTAssertEqual(s.daysBetween(DayKey(rawValue: "2026-07-18"), DayKey(rawValue: "2026-07-19")), 1)
        XCTAssertEqual(s.daysBetween(DayKey(rawValue: "2026-07-01"), DayKey(rawValue: "2026-06-30")), -1)
    }

    func testDayKeyComparableIsChronological() {
        XCTAssertLessThan(DayKey(rawValue: "2026-07-09"), DayKey(rawValue: "2026-07-10"))
    }

    func testWeekKeyIsISO() {
        let s = makeService()
        XCTAssertEqual(s.currentWeek.rawValue, "2026-W29")
    }
}
