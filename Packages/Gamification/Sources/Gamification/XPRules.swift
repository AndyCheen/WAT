import Foundation

/// Таблиця нарахувань XP — стартовий баланс (PLAN.md §13.2, потребує підтвердження).
/// Усі числа зібрані тут, щоб перебалансувати гру не чіпаючи логіку.
public struct XPRules: Sendable {
    public var perIntake: Int
    public var perDayPartGoal: Int
    public var perDailyGoal: Int
    public var perDailyQuest: Int
    public var perWeeklyQuest: Int
    public var streakMultiplierStep: Double
    public var streakMultiplierCap: Double

    public init(
        perIntake: Int = 5,
        perDayPartGoal: Int = 10,
        perDailyGoal: Int = 50,
        perDailyQuest: Int = 25,
        perWeeklyQuest: Int = 100,
        streakMultiplierStep: Double = 0.05,
        streakMultiplierCap: Double = 1.5
    ) {
        self.perIntake = perIntake
        self.perDayPartGoal = perDayPartGoal
        self.perDailyGoal = perDailyGoal
        self.perDailyQuest = perDailyQuest
        self.perWeeklyQuest = perWeeklyQuest
        self.streakMultiplierStep = streakMultiplierStep
        self.streakMultiplierCap = streakMultiplierCap
    }

    /// Серія збільшує коефіцієнт досвіду (ТЗ §5.3).
    public func multiplier(streak: Int) -> Double {
        min(streakMultiplierCap, 1 + Double(max(0, streak)) * streakMultiplierStep)
    }

    public static let `default` = XPRules()
}

/// Що робити з нарахуваннями, якщо користувач відмінив дію (ТЗ §5.2).
public enum RevertPolicy: Sendable {
    /// Повний відкат: XP повертається, завдання й досягнення знімаються,
    /// якщо умова більше не виконується.
    case full
    /// Досягнення й завдання лишаються, повертається тільки XP за саму дію.
    case keepProgress
}
