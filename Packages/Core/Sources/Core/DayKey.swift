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
