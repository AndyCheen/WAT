import Foundation

/// Календарні обчислення застосунку: межі доби, ключі періодів, навігація місяцями.
///
/// Новий день починається о 00:00 локального часу (ТЗ §14).
public struct CalendarService: Sendable {
    public let clock: Clock
    public let calendar: Calendar

    public init(clock: Clock) {
        self.clock = clock
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = clock.timeZone
        cal.firstWeekday = 2 // понеділок — усі макети починають тиждень з «Пн»
        cal.locale = Locale(identifier: "uk_UA")
        self.calendar = cal
    }

    public var now: Date { clock.now }
    public var today: DayKey { DayKey(date: clock.now, calendar: calendar) }
    public var currentWeek: WeekKey { WeekKey(date: clock.now, calendar: calendar) }
    public var currentMonth: MonthKey { MonthKey(date: clock.now, calendar: calendar) }

    public func dayKey(for date: Date) -> DayKey { DayKey(date: date, calendar: calendar) }
    public func weekKey(for date: Date) -> WeekKey { WeekKey(date: date, calendar: calendar) }
    public func monthKey(for date: Date) -> MonthKey { MonthKey(date: date, calendar: calendar) }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func date(from key: DayKey) -> Date {
        var c = DateComponents()
        c.year = key.year; c.month = key.month; c.day = key.day
        c.hour = 0; c.minute = 0; c.second = 0
        return calendar.date(from: c) ?? clock.now
    }

    public func date(from key: MonthKey) -> Date {
        var c = DateComponents()
        c.year = key.year; c.month = key.month; c.day = 1
        return calendar.date(from: c) ?? clock.now
    }

    public func dayKey(offsetDays: Int, from key: DayKey) -> DayKey {
        let base = date(from: key)
        let shifted = calendar.date(byAdding: .day, value: offsetDays, to: base) ?? base
        return DayKey(date: shifted, calendar: calendar)
    }

    /// Останні `count` діб, включно з `endingAt` (за замовчуванням — сьогодні). Від старіших до новіших.
    public func recentDays(_ count: Int, endingAt end: DayKey? = nil) -> [DayKey] {
        let last = end ?? today
        return (0..<count).reversed().map { dayKey(offsetDays: -$0, from: last) }
    }

    /// Вікно з `count` діб, що закінчується сьогоднішнім днем, але не починається раніше
    /// за `anchor` — день, з якого історію взагалі має сенс показувати.
    ///
    /// Поки від `anchor` минуло менше ніж `count` діб, вікно стоїть на місці: дні, яких ще
    /// не було, лишаються в кінці масиву, і рядок заповнюється зліва направо. Далі вікно
    /// починає ковзати разом із сьогоднішнім днем, показуючи останні `count` діб (WAT-11).
    ///
    /// Перемикання між двома фазами навмисне не має окремого стану — воно випливає з `max`.
    /// `anchor` ставиться один раз (на першому закритому дні); на новій серії його не
    /// переносять, інакше після зриву рядок стрибав би на початок.
    public func slidingWindow(_ count: Int, anchor: DayKey?, endingAt end: DayKey? = nil) -> [DayKey] {
        let last = end ?? today
        let rollingStart = dayKey(offsetDays: -(count - 1), from: last)
        let start = anchor.map { max($0, rollingStart) } ?? rollingStart
        return (0..<count).map { dayKey(offsetDays: $0, from: start) }
    }

    public func monthKey(offsetMonths: Int, from key: MonthKey) -> MonthKey {
        let base = date(from: key)
        let shifted = calendar.date(byAdding: .month, value: offsetMonths, to: base) ?? base
        return MonthKey(date: shifted, calendar: calendar)
    }

    public func numberOfDays(in month: MonthKey) -> Int {
        let d = date(from: month)
        return calendar.range(of: .day, in: .month, for: d)?.count ?? 30
    }

    /// Скільки порожніх комірок треба перед 1-м числом у сітці, що починається з понеділка.
    public func leadingBlanks(in month: MonthKey) -> Int {
        let first = date(from: month)
        let weekday = calendar.component(.weekday, from: first) // нд = 1
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Різниця в добах між двома ключами (rhs - lhs).
    public func daysBetween(_ lhs: DayKey, _ rhs: DayKey) -> Int {
        let a = startOfDay(date(from: lhs))
        let b = startOfDay(date(from: rhs))
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    public func hour(of date: Date) -> Int { calendar.component(.hour, from: date) }

    public func isToday(_ key: DayKey) -> Bool { key == today }
    public func isFuture(_ key: DayKey) -> Bool { key > today }

    public static let weekdayLabels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]

    public static let monthNames = [
        "Січень", "Лютий", "Березень", "Квітень", "Травень", "Червень",
        "Липень", "Серпень", "Вересень", "Жовтень", "Листопад", "Грудень"
    ]

    public static let monthNamesGenitive = [
        "січня", "лютого", "березня", "квітня", "травня", "червня",
        "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
    ]

    public func monthTitle(_ key: MonthKey) -> String {
        let idx = max(1, min(12, key.month)) - 1
        return "\(Self.monthNames[idx]) \(key.year)"
    }
}
