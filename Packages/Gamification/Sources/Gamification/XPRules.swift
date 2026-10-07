import Foundation

/// Таблиця нарахувань XP — стартовий баланс (PLAN.md §13.2, потребує підтвердження).
/// Усі числа зібрані тут, щоб перебалансувати гру не чіпаючи логіку.
///
/// XP за воду, крок об'єму й загальний множник ще й налаштовуються без коду — з `Config/Balance.xcconfig`
/// через `applyingBalance(_:)` (SPEC-PRIZES §16.13).
public struct XPRules: Sendable, Equatable {
    /// XP за кожні `volumeStepMl` мл **зарахованого** за день (у межах стелі 120 %), а не за порцію:
    /// за порцію XP заохочував би дрібнити воду й пити понад норму (SPEC-PRIZES §16.13).
    public var xpPerVolumeStep: Int
    public var volumeStepMl: Int
    /// Множить увесь XP — воду, норму, частини доби, завдання, досягнення. Перемножується з серією й бустом.
    public var xpMultiplier: Double
    public var perDayPartGoal: Int
    public var perDailyGoal: Int
    public var perDailyQuest: Int
    public var perWeeklyQuest: Int
    public var streakMultiplierStep: Double
    public var streakMultiplierCap: Double

    // Нагороди за повернення (SPEC-NOTIFICATIONS §12.5).
    /// «Знову в ритмі» — як щоденне завдання.
    public var perBounceBack: Int
    /// Серія, обрив якої вартий бонусу: інакше чергування «норма — пропуск — норма» стало б фармом.
    public var bounceBackMinStreak: Int
    public var bounceBackCooldownDays: Int
    /// `daysBetween(останній день з порцією, сьогодні)` — з якого розриву перша порція дає подарунок.
    public var comebackMinGapDays: Int
    /// Не частіше: інакше «пропущу 3 дні — отримаю приз» стає стратегією.
    public var comebackCooldownDays: Int

    public init(
        xpPerVolumeStep: Int = 5,
        volumeStepMl: Int = 250,
        xpMultiplier: Double = 1,
        perDayPartGoal: Int = 10,
        perDailyGoal: Int = 50,
        perDailyQuest: Int = 25,
        perWeeklyQuest: Int = 100,
        streakMultiplierStep: Double = 0.05,
        streakMultiplierCap: Double = 1.5,
        perBounceBack: Int = 25,
        bounceBackMinStreak: Int = 3,
        bounceBackCooldownDays: Int = 7,
        comebackMinGapDays: Int = 3,
        comebackCooldownDays: Int = 30
    ) {
        self.xpPerVolumeStep = xpPerVolumeStep
        self.volumeStepMl = volumeStepMl
        self.xpMultiplier = xpMultiplier
        self.perDayPartGoal = perDayPartGoal
        self.perDailyGoal = perDailyGoal
        self.perDailyQuest = perDailyQuest
        self.perWeeklyQuest = perWeeklyQuest
        self.streakMultiplierStep = streakMultiplierStep
        self.streakMultiplierCap = streakMultiplierCap
        self.perBounceBack = perBounceBack
        self.bounceBackMinStreak = bounceBackMinStreak
        self.bounceBackCooldownDays = bounceBackCooldownDays
        self.comebackMinGapDays = comebackMinGapDays
        self.comebackCooldownDays = comebackCooldownDays
    }

    /// Серія збільшує коефіцієнт досвіду (ТЗ §5.3).
    public func multiplier(streak: Int) -> Double {
        min(streakMultiplierCap, 1 + Double(max(0, streak)) * streakMultiplierStep)
    }

    /// XP за порцію — приріст накопиченого за день: ⌊k·після⌋ − ⌊k·до⌋. Так п'ять порцій по 50 мл дають
    /// рівно стільки, скільки одна на 250, а округлення кожної порції окремо не дає зайвого XP.
    /// Аргументи — **зараховане** (вже обрізане стелею), тож понад стелю приріст нульовий.
    public func waterXp(countedBefore: Int, countedAfter: Int) -> Int {
        guard volumeStepMl > 0, xpPerVolumeStep > 0, countedAfter > countedBefore else { return 0 }
        let earned: (Int) -> Int = { max(0, $0) * self.xpPerVolumeStep / self.volumeStepMl }
        return earned(countedAfter) - earned(countedBefore)
    }

    public static let `default` = XPRules()

    // MARK: - Баланс із конфігурації

    /// Імена ключів однакові в `Config/Balance.xcconfig`, `Info.plist` і змінних середовища DEBUG.
    public enum BalanceKey {
        public static let xpPerVolumeStep = "WT_XP_PER_VOLUME_STEP"
        public static let volumeStepMl = "WT_XP_VOLUME_STEP_ML"
        public static let xpMultiplier = "WT_XP_MULTIPLIER"
        public static let all = [xpPerVolumeStep, volumeStepMl, xpMultiplier]
    }

    /// Ті самі правила з балансом із конфігурації. Значення, що не читається (не число чи ≤ 0, а також
    /// нерозкрита змінна збірки `$(…)`), лишає типове — зламаний конфіг не має обнулити XP.
    public func applyingBalance(_ values: [String: String]) -> XPRules {
        var rules = self
        func positive<T: LosslessStringConvertible & Comparable & Numeric>(_ key: String, _: T.Type) -> T? {
            guard let raw = values[key]?.trimmingCharacters(in: .whitespaces),
                  let value = T(raw.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
            return value
        }
        if let value = positive(BalanceKey.xpPerVolumeStep, Int.self) { rules.xpPerVolumeStep = value }
        if let value = positive(BalanceKey.volumeStepMl, Int.self) { rules.volumeStepMl = value }
        if let value = positive(BalanceKey.xpMultiplier, Double.self) { rules.xpMultiplier = value }
        return rules
    }
}

/// Що робити з нарахуваннями, якщо користувач відмінив дію (ТЗ §5.2).
public enum RevertPolicy: Sendable {
    /// Повний відкат: XP повертається, завдання й досягнення знімаються,
    /// якщо умова більше не виконується.
    case full
    /// Досягнення й завдання лишаються, повертається тільки XP за саму дію.
    case keepProgress
}
