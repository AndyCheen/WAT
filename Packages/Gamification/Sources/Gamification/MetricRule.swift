import Foundation
import Core
import Persistence
import Metrics

/// Контекст обчислення правила — все, від чого може залежати умова.
@MainActor
public struct RuleContext {
    public let metrics: MetricsService
    public let calendar: CalendarService
    public let date: Date
    public let dailyGoalMl: Int
    public let currentStreak: Int
    public let longestStreak: Int

    public init(
        metrics: MetricsService,
        calendar: CalendarService,
        date: Date,
        dailyGoalMl: Int,
        currentStreak: Int,
        longestStreak: Int
    ) {
        self.metrics = metrics
        self.calendar = calendar
        self.date = date
        self.dailyGoalMl = dailyGoalMl
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }
}

/// Декларативна умова поверх реєстру метрик.
/// Нове завдання чи досягнення — це рядок у каталозі, а не новий код.
public struct MetricRule: Sendable {
    public enum Aggregate: Sendable { case sum, count, max }

    public enum Source: Sendable {
        case metric(MetricKey, MetricPeriodType, Aggregate)
        /// Поточна серія — читається зі стану, тому чесно зменшується після відкату.
        case currentStreak
        /// Найдовша серія за всю історію.
        case longestStreak
    }

    public let source: Source

    public init(source: Source) {
        self.source = source
    }

    public init(key: MetricKey, period: MetricPeriodType = .all, aggregate: Aggregate = .sum) {
        self.source = .metric(key, period, aggregate)
    }

    public static let currentStreak = MetricRule(source: .currentStreak)
    public static let longestStreak = MetricRule(source: .longestStreak)

    @MainActor
    public func value(in context: RuleContext) -> Double {
        switch source {
        case .currentStreak:
            return Double(context.currentStreak)
        case .longestStreak:
            return Double(context.longestStreak)
        case let .metric(key, period, aggregate):
            let periodKey = Self.periodKey(period, calendar: context.calendar, at: context.date)
            switch aggregate {
            case .sum: return context.metrics.sum(key, periodType: period, periodKey: periodKey)
            case .count: return Double(context.metrics.count(key, periodType: period, periodKey: periodKey))
            case .max: return context.metrics.maxValue(key, periodType: period, periodKey: periodKey)
            }
        }
    }

    public static func periodKey(_ period: MetricPeriodType, calendar: CalendarService, at date: Date) -> String {
        switch period {
        case .day: return calendar.dayKey(for: date).rawValue
        case .week: return calendar.weekKey(for: date).rawValue
        case .month: return calendar.monthKey(for: date).rawValue
        case .year: return String(calendar.dayKey(for: date).year)
        case .all: return MetricsService.allTimeKey
        }
    }
}
