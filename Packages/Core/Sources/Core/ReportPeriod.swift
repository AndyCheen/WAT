import Foundation

/// Період звіту (SPEC-NOTIFICATIONS §11): день, тиждень з понеділка або календарний місяць.
///
/// Тиждень задається днем-понеділком, а не `WeekKey`: ISO-номер тижня на межі року належить
/// іншому року, а звіту потрібні саме сім днів поспіль.
public enum ReportPeriod: Hashable, Sendable {
    case day(DayKey)
    case week(start: DayKey)
    case month(MonthKey)

    public enum Kind: String, CaseIterable, Sendable {
        case day, week, month
    }

    public var kind: Kind {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        }
    }

    /// `day:2026-10-04`, `week:2026-09-21`, `month:2026-09` — для `userInfo` сповіщення й прапорців запуску.
    public var encoded: String {
        switch self {
        case .day(let day): return "day:\(day.rawValue)"
        case .week(let start): return "week:\(start.rawValue)"
        case .month(let month): return "month:\(month.rawValue)"
        }
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]) else { return nil }
        switch kind {
        case .day: self = .day(DayKey(rawValue: parts[1]))
        case .week: self = .week(start: DayKey(rawValue: parts[1]))
        case .month: self = .month(MonthKey(rawValue: parts[1]))
        }
    }
}

extension CalendarService {
    /// 0 — понеділок … 6 — неділя.
    public func weekdayIndex(of day: DayKey) -> Int {
        (calendar.component(.weekday, from: date(from: day)) + 5) % 7
    }

    public func isWeekend(_ day: DayKey) -> Bool { weekdayIndex(of: day) >= 5 }

    public func weekStart(of day: DayKey) -> DayKey {
        dayKey(offsetDays: -weekdayIndex(of: day), from: day)
    }

    public func monthKey(of day: DayKey) -> MonthKey { MonthKey(year: day.year, month: day.month) }

    /// Період заданого виду, що містить `day`.
    public func period(_ kind: ReportPeriod.Kind, containing day: DayKey) -> ReportPeriod {
        switch kind {
        case .day: return .day(day)
        case .week: return .week(start: weekStart(of: day))
        case .month: return .month(monthKey(of: day))
        }
    }

    /// Дні періоду від першого до останнього.
    public func days(in period: ReportPeriod) -> [DayKey] {
        switch period {
        case .day(let day):
            return [day]
        case .week(let start):
            return (0..<7).map { dayKey(offsetDays: $0, from: start) }
        case .month(let month):
            let first = DayKey(rawValue: String(format: "%04d-%02d-01", month.year, month.month))
            return (0..<numberOfDays(in: month)).map { dayKey(offsetDays: $0, from: first) }
        }
    }

    /// Попередній (`-1`) чи наступний (`+1`) період того самого виду.
    public func shifted(_ period: ReportPeriod, by offset: Int) -> ReportPeriod {
        switch period {
        case .day(let day): return .day(dayKey(offsetDays: offset, from: day))
        case .week(let start): return .week(start: dayKey(offsetDays: 7 * offset, from: start))
        case .month(let month): return .month(monthKey(offsetMonths: offset, from: month))
        }
    }
}
