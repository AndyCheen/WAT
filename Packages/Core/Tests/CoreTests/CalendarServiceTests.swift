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

    // MARK: - Вікно крапок (WAT-11)
    //
    // Референсна точка — 18 липня 2026. Якір ставиться на першому дні з даними.

    /// Поки даних менше семи днів, вікно стоїть на якорі: дні, яких ще не було,
    /// висять у хвості, і рядок заповнюється зліва направо.
    func testSlidingWindowStaysAnchoredWhileHistoryIsShort() {
        let s = makeService()
        let anchor = DayKey(rawValue: "2026-07-16") // позавчора — три дні історії
        let days = s.slidingWindow(7, anchor: anchor).map(\.rawValue)

        XCTAssertEqual(days.first, "2026-07-16", "вікно стоїть на першому дні з даними")
        XCTAssertEqual(days[2], "2026-07-18", "сьогодні — третя позиція, решта попереду")
        XCTAssertEqual(days.last, "2026-07-22", "хвіст — дні, яких ще не було")
    }

    /// Перший день користування: сьогодні ліворуч, шість порожніх позицій попереду.
    func testSlidingWindowOnFirstDay() {
        let s = makeService()
        let days = s.slidingWindow(7, anchor: s.today).map(\.rawValue)
        XCTAssertEqual(days.first, "2026-07-18")
        XCTAssertEqual(days.last, "2026-07-24")
    }

    /// Щойно історії стало сім днів, вікно починає ковзати: сьогодні крайнє праворуч.
    func testSlidingWindowStartsRollingOnceHistoryIsLongEnough() {
        let s = makeService()
        let days = s.slidingWindow(7, anchor: DayKey(rawValue: "2026-07-01")).map(\.rawValue)
        XCTAssertEqual(days.first, "2026-07-12")
        XCTAssertEqual(days.last, "2026-07-18", "сьогодні — крайнє праворуч")
    }

    /// Рівно сім днів історії — межа переходу: якір ще збігається з початком вікна.
    func testSlidingWindowBoundaryDay() {
        let s = makeService()
        let days = s.slidingWindow(7, anchor: DayKey(rawValue: "2026-07-12")).map(\.rawValue)
        XCTAssertEqual(days.first, "2026-07-12")
        XCTAssertEqual(days.last, "2026-07-18")
    }

    /// Без даних якоря немає — поводимось як звичайне ковзне вікно.
    func testSlidingWindowWithoutAnchorIsRolling() {
        let s = makeService()
        XCTAssertEqual(s.slidingWindow(7, anchor: nil).map(\.rawValue), s.recentDays(7).map(\.rawValue))
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
