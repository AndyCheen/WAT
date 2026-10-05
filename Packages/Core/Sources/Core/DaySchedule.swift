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

    /// Крива темпу цього дня для норми `goalMl`.
    public func curve(goalMl: Int) -> PaceCurve {
        PaceCurve(goalMl: goalMl, wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes)
    }
}
