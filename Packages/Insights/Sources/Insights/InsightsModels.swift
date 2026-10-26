import Foundation
import Core

/// Рядок графіка «Рівномірність за день» (макет 4a) — блок цілі частини доби (`GoalBlock`), а не
/// одна з 5 `DayPart` (рішення від 13.10.2026, WAT-47): «✓» тут — та сама, що у віджета, чекпоінта,
/// XP `dayPartGoal` і звіту. Годинний «ранок» 08–09 із ціллю 138 мл закривався першою склянкою, а
/// віджет показував «до 12 — ✓», коли графік казав «полудень не закрито».
public struct EvennessRow: Equatable, Identifiable, Sendable {
    public let parts: [DayPart]
    public let fromMinute: Int
    public let toMinute: Int
    public let ml: Int
    public let targetMl: Int
    /// Частка цілі блоку — ширина синьої смуги: повна смуга і є ціль, понад ціль — теж повна.
    public let fraction: Double

    public var id: Int { fromMinute }
    /// Злитий блок «ранок і полудень» 08–12 — «Ранок»: години поруч кажуть решту.
    public var label: String { parts[0].title }
    /// «08–12» / «8–12 пп» — як у віджеті «Ритм дня», у форматі людини (WAT-58).
    public func hoursLabel(_ format: TimeFormat = .hours24) -> String { format.hourRange(fromMinute, toMinute) }
    public var isReached: Bool { targetMl > 0 && GoalBlock.isReached(drunkMl: ml, targetMl: targetMl) }
}

/// Випите в частині доби — стовпчики «Деталей дня». Тут лишаються 5 частин: це розподіл, а не оцінка.
public struct DayPartTotal: Equatable, Identifiable, Sendable {
    public let part: DayPart
    public let ml: Int

    public var id: Int { part.rawValue }
    public var label: String { part.title }
}

public struct EvennessReport: Equatable, Sendable {
    public let score: Int
    public let rows: [EvennessRow]
    public let totalMl: Int
    /// «Ритм дня» вимкнено (§28) — як у віджетах: без «✓» і без «з цілі», лише мілілітри.
    public let dayRhythmEnabled: Bool

    public init(score: Int, rows: [EvennessRow], totalMl: Int, dayRhythmEnabled: Bool) {
        self.score = score
        self.rows = rows
        self.totalMl = totalMl
        self.dayRhythmEnabled = dayRhythmEnabled
    }

    public static let empty = EvennessReport(score: 0, rows: [], totalMl: 0, dayRhythmEnabled: true)
}

/// Рядок графіка «Типова доба — медіана і розкид» (макет 4a).
public struct TypicalDayRow: Equatable, Identifiable, Sendable {
    public let part: DayPart
    /// Усі частки — від 0 до 1 від денного обʼєму.
    public let median: Double
    public let low: Double
    public let high: Double
    /// Цільова частка з кривої темпу; `nil` — частина поза активними годинами.
    public let ideal: Double?

    public var id: Int { part.rawValue }
    public var label: String { part.title }
    public var percentLabel: String { "\(Int((median * 100).rounded()))%" }
}

public struct TypicalDayReport: Equatable, Sendable {
    public let rows: [TypicalDayRow]
    public let daysCounted: Int

    public static let empty = TypicalDayReport(rows: [], daysCounted: 0)
}

/// Комірка теплокарти «Коли ти пʼєш».
public struct HeatmapCell: Equatable, Identifiable, Sendable {
    public let weekdayIndex: Int
    public let hourBucket: Int
    public let ml: Int
    /// Рівень інтенсивності 0…4 — точно як 5 кольорів у макеті.
    public let level: Int

    public var id: String { "\(weekdayIndex).\(hourBucket)" }
}

public struct HeatmapReport: Equatable, Sendable {
    public let hours: [Int]
    public let rows: [[HeatmapCell]]
    public let subtitle: String
    public let daysCounted: Int

    public static let empty = HeatmapReport(hours: [], rows: [], subtitle: "", daysCounted: 0)
}

/// Стовпчик графіка «Обʼєм по днях».
public struct VolumeBar: Equatable, Identifiable, Sendable {
    public let label: String
    public let ml: Int
    public let goalMl: Int
    public let key: String

    public var id: String { key }
    public var goalMet: Bool { ml >= goalMl }
}

public struct VolumeChartReport: Equatable, Sendable {
    public let bars: [VolumeBar]
    public let goalMl: Int
    public let maxValue: Int

    public static let empty = VolumeChartReport(bars: [], goalMl: 0, maxValue: 0)

    public func fraction(_ bar: VolumeBar) -> Double {
        maxValue > 0 ? Double(bar.ml) / Double(maxValue) : 0
    }

    public var goalFraction: Double {
        maxValue > 0 ? Double(goalMl) / Double(maxValue) : 0
    }
}

/// Комірка календаря-теплокарти (макет 4a).
public struct CalendarDay: Equatable, Identifiable, Sendable {
    public let dayKey: DayKey?
    public let number: Int?
    public let completionPct: Int
    public let goalMet: Bool
    public let isToday: Bool
    public let isFuture: Bool
    public let hasData: Bool

    public var id: String { dayKey?.rawValue ?? "blank-\(number ?? 0)-\(isFuture)" }
    public var isBlank: Bool { number == nil }

    /// Насиченість кольору: 0…1 від % норми (обрізається на 100 %).
    public var intensity: Double { min(1, Double(completionPct) / 100) }

    public static func blank(index: Int) -> CalendarDay {
        CalendarDay(
            dayKey: nil, number: nil, completionPct: 0, goalMet: false,
            isToday: false, isFuture: false, hasData: false
        )
    }
}

public struct CalendarMonthReport: Equatable, Sendable {
    public let month: MonthKey
    public let title: String
    public let days: [CalendarDay]
    public let hasData: Bool
    public let canGoBack: Bool
    public let canGoForward: Bool
}

/// Деталі обраного дня: ритм по частинах доби + історія внесень.
public struct DayDetailReport: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let amountMl: Int
        public let timeLabel: String
    }

    public let dayKey: DayKey
    public let title: String
    public let totalMl: Int
    public let goalMl: Int
    public let completionPct: Int
    public let rhythm: [DayPartTotal]
    public let entries: [Entry]

    public var hasEntries: Bool { !entries.isEmpty }
    public var litersLabel: String { Volume.litersLabel(totalMl) }
}

/// Зведення для шторки статистики на 1a.
public struct WeekSummary: Equatable, Sendable {
    public let bars: [VolumeBar]
    public let averageMl: Int
    public let bestMl: Int
    public let totalMl: Int

    public static let empty = WeekSummary(bars: [], averageMl: 0, bestMl: 0, totalMl: 0)
}

public enum StatsPeriod: Int, CaseIterable, Sendable, Identifiable {
    case week7 = 0
    case month30 = 1

    public var id: Int { rawValue }
    public var title: String { self == .week7 ? "7 днів" : "30 днів" }
    public var days: Int { self == .week7 ? 7 : 30 }
}

public enum VolumeChartMode: Int, CaseIterable, Sendable, Identifiable {
    case days7 = 0
    case weeks8 = 1
    /// 12 місяців (ТЗ §7 «рік», WAT-67): середнє за активний день місяця проти денної норми — місяці різної довжини
    /// й неповний поточний місяць суми порівнювати не дали б.
    case months12 = 2

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .days7: return "7 днів"
        case .weeks8: return "8 тижнів"
        case .months12: return "Рік"
        }
    }
}
