import Foundation

/// Реєстр метрик — єдине джерело правди для завдань, досягнень і графіків (PLAN.md §4).
///
/// Нова механіка не додає код у чужі модулі: вона або публікує нову метрику,
/// або описує правило поверх наявної.
public struct MetricKey: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    // Вода
    public static let intakeAdded: MetricKey = "intake.added"
    public static let intakeCount: MetricKey = "intake.count"
    public static let intakeRemoved: MetricKey = "intake.removed"
    public static let intakeRestored: MetricKey = "intake.restored"
    public static let dayTotal: MetricKey = "day.total"
    public static let dayGoalMet: MetricKey = "day.goalMet"
    public static let dayCompletionPct: MetricKey = "day.completionPct"

    // Частини доби
    public static let partMorning: MetricKey = "part.morning"
    public static let partNoon: MetricKey = "part.noon"
    public static let partAfternoon: MetricKey = "part.afternoon"
    public static let partEvening: MetricKey = "part.evening"
    public static let partNight: MetricKey = "part.night"

    // Гейміфікація
    public static let streakCurrent: MetricKey = "streak.current"
    public static let xpEarned: MetricKey = "xp.earned"
    public static let levelReached: MetricKey = "level.reached"
    public static let questCompleted: MetricKey = "quest.completed"
    public static let achievementUnlocked: MetricKey = "achievement.unlocked"
    public static let prizeActivated: MetricKey = "prize.activated"

    // Поведінка
    public static let appOpened: MetricKey = "app.opened"
    public static let reminderResponded: MetricKey = "reminder.responded"

    public static func part(_ index: Int) -> MetricKey {
        [partMorning, partNoon, partAfternoon, partEvening, partNight][max(0, min(4, index))]
    }
}
