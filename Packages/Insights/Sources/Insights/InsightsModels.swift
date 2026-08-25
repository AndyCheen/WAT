import Foundation
import Core

/// Рядок графіка «Рівномірність за день» (макет 4a).
public struct EvennessRow: Equatable, Identifiable, Sendable {
    public let part: DayPart
    public let ml: Int
    public let idealMl: Int
    /// Частка від максимуму на графіку — ширина синьої смуги.
    public let fraction: Double
    /// Позиція ризки «ціль» у тих самих координатах.
    public let tickFraction: Double

    public var id: Int { part.rawValue }
    public var label: String { part.title }
}

public struct EvennessReport: Equatable, Sendable {
    public let score: Int
    public let rows: [EvennessRow]
    public let totalMl: Int

    public static let empty = EvennessReport(score: 0, rows: [], totalMl: 0)
}

/// Рядок графіка «Типова доба — медіана і розкид» (макет 4a).
public struct TypicalDayRow: Equatable, Identifiable, Sendable {
    public let part: DayPart
    /// Усі частки — від 0 до 1 від денного обʼєму.
    public let median: Double
    public let low: Double
    public let high: Double
    public let ideal: Double

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
    public let rhythm: [EvennessRow]
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

    public var id: Int { rawValue }
    public var title: String { self == .days7 ? "7 днів" : "8 тижнів" }
}
