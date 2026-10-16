import Foundation

/// Ключ доби у форматі `yyyy-MM-dd` за локальним календарем користувача.
///
/// Рядкове подання навмисне: воно стабільне при зміні часового поясу, придатне
/// для унікального індексу в БД і для сортування (лексикографічне == хронологічне).
public struct DayKey: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public var description: String { rawValue }
    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.rawValue < rhs.rawValue }

    public var year: Int { Int(rawValue.prefix(4)) ?? 0 }
    public var month: Int { Int(rawValue.dropFirst(5).prefix(2)) ?? 0 }
    public var day: Int { Int(rawValue.suffix(2)) ?? 0 }
}

extension DayKey {
    /// Номер доби від 1970-01-01 — чиста арифметика без `Calendar` (`days_from_civil`
    /// Г. Гіннанта). Правила досягнень ходять історією день за днем, а `Calendar` на кожен
    /// крок коштував би мілісекунди на порцію (WAT-24).
    public var ordinal: Int { Self.ordinal(year: year, month: month, day: day) }

    public init(ordinal: Int) {
        let (y, m, d) = Self.civil(fromOrdinal: ordinal)
        self.init(rawValue: String(format: "%04d-%02d-%02d", y, m, d))
    }

    /// 0 — понеділок … 6 — неділя: 1970-01-01 був четвергом.
    public var weekdayIndex: Int { Self.weekdayIndex(ordinal: ordinal) }

    public static func weekdayIndex(ordinal: Int) -> Int {
        ((ordinal + 3) % 7 + 7) % 7
    }

    public static func ordinal(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public static func civil(fromOrdinal ordinal: Int) -> (year: Int, month: Int, day: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// Ключ тижня `yyyy-Www` (ISO-8601) — період для тижневих челенджів.
public struct WeekKey: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(date: Date, calendar: Calendar) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        self.rawValue = String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    public var description: String { rawValue }
    public static func < (lhs: WeekKey, rhs: WeekKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Ключ місяця `yyyy-MM`.
public struct MonthKey: Hashable, Codable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.rawValue = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    public init(year: Int, month: Int) {
        self.rawValue = String(format: "%04d-%02d", year, month)
    }

    public var year: Int { Int(rawValue.prefix(4)) ?? 0 }
    public var month: Int { Int(rawValue.suffix(2)) ?? 0 }
    public var description: String { rawValue }
    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { lhs.rawValue < rhs.rawValue }
}
