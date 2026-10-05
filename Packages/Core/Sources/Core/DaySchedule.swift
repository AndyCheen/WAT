import Foundation

/// Активні години `[W, S]` одного дня, у хвилинах від 00:00.
///
/// У `Core`, а не в `Notifications`: з цих годин рахуються і сповіщення, і XP за частину доби
/// (`Gamification`), і цілі частин доби в звіті (`Insights`) — модулі, що один одного не імпортують.
public struct DaySchedule: Sendable, Equatable {
    public var wakeMinutes: Int
    public var sleepMinutes: Int

    public init(wakeMinutes: Int, sleepMinutes: Int) {
        self.wakeMinutes = wakeMinutes
        self.sleepMinutes = sleepMinutes
    }

    public static let weekdayDefault = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    // Межі розкладу — одні для екрана «Сповіщення», вікна «Графік дня» й пропозиції з `Insights` (WAT-41).
    // Відбій не пізніше 24:00: доба застосунку закінчується опівночі (SPEC-NOTIFICATIONS §16.6).
    public static let earliestWakeMinutes = 4 * 60
    public static let latestSleepMinutes = 24 * 60
    public static let minActiveMinutes = 6 * 60
    public static let stepMinutes = 15

    /// Крива темпу цього дня для норми `goalMl`.
    public func curve(goalMl: Int) -> PaceCurve {
        PaceCurve(goalMl: goalMl, wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes)
    }

    /// Підйом на крок 15 хв у межах: від 04:00 і не менше 6 год до відбою.
    public func steppingWake(_ direction: Int) -> DaySchedule {
        var next = self
        next.wakeMinutes = Self.clamp(wakeMinutes + direction * Self.stepMinutes,
                                      Self.earliestWakeMinutes, sleepMinutes - Self.minActiveMinutes)
        return next
    }

    /// Відбій на крок 15 хв у межах: не менше 6 год після підйому й не пізніше 24:00.
    public func steppingSleep(_ direction: Int) -> DaySchedule {
        var next = self
        next.sleepMinutes = Self.clamp(sleepMinutes + direction * Self.stepMinutes,
                                       wakeMinutes + Self.minActiveMinutes, Self.latestSleepMinutes)
        return next
    }

    /// «06:30–22:00».
    public var label: String { "\(Self.clock(wakeMinutes))–\(Self.clock(sleepMinutes))" }

    public static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), max(low, high))
    }
}

/// Увесь розклад: будні й, якщо увімкнено, окремо вихідні.
///
/// Значення, а не `UserProfile`: пропозицію графіка рахує чиста функція в `Insights` (WAT-41).
public struct WeekSchedule: Sendable, Equatable {
    public var weekday: DaySchedule
    public var weekendEnabled: Bool
    /// Зберігається й при вимкненому окремому розкладі — як у профілі.
    public var weekend: DaySchedule

    public init(weekday: DaySchedule, weekendEnabled: Bool, weekend: DaySchedule) {
        self.weekday = weekday
        self.weekendEnabled = weekendEnabled
        self.weekend = weekend
    }

    /// Розклад, що діє в такий день: у суботу й неділю — окремий, якщо його увімкнено.
    public func schedule(isWeekend: Bool) -> DaySchedule {
        isWeekend && weekendEnabled ? weekend : weekday
    }
}
