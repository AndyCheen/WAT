import Foundation
import Persistence

/// Внутрішні константи сповіщень — те, що не виноситься в UI (SPEC-NOTIFICATIONS §15.2).
///
/// За зразком `XPRules`: усі числа зібрані тут, щоб перебалансувати, не чіпаючи логіку.
/// Константи етапів B і C (чекпоінти, несподівані завдання) додадуться разом із ними.
public struct NotificationRules: Sendable {
    /// Параметри нагадування за темпом: нагадуємо, коли `E(t) − R ≥ k·P`, але не раніше
    /// `minGap` і не пізніше `maxGap` від якоря (§6.2).
    public struct Pace: Sendable, Equatable {
        public var k: Double
        public var minGapMinutes: Int
        public var maxGapMinutes: Int

        public init(k: Double, minGapMinutes: Int, maxGapMinutes: Int) {
            self.k = k
            self.minGapMinutes = minGapMinutes
            self.maxGapMinutes = maxGapMinutes
        }
    }

    /// Повторне — через 30 хв: покриває більшість станів «зайнятий» (§6.1, висновок 4).
    public var followUpMinutes = 30
    /// Між повторним і наступним основним: проігнороване — сигнал рідшати.
    public var blockBackoffMinutes = 120
    /// Після двох проігнорованих блоків — пауза до порції або відкриття застосунку.
    public var maxUnansweredBlocks = 2
    public var pace: [ReminderFrequency: Pace] = [
        .rarer: Pace(k: 1.5, minGapMinutes: 90, maxGapMinutes: 240),
        .normal: Pace(k: 1.0, minGapMinutes: 60, maxGapMinutes: 180),
        .more: Pace(k: 0.75, minGapMinutes: 45, maxGapMinutes: 120)
    ]

    /// Активних на день (усі типи, крім тихих звітів і відлуння) — §13.1.
    public var dailyCap = 8
    /// Мінімальний проміжок між будь-якими двома; він же вікно колізії (§13.3).
    public var minSpacingMinutes = 30
    /// Порція протягом цього часу після доставки — сповіщення виконане (§3.2).
    public var responseWindowMinutes = 60

    /// «Можна закрити» ввечері: бракує ≤ min(2·P, 600 мл) (§8).
    public var closableMultiplier = 2.0
    /// Стеля для здоров'я: більше за 2 години перед сном — перебитий сон, а не користь.
    public var eveningCapMl = 600
    public var eveningLeadMinutes = 120
    /// Відсічка нагадувань, якщо вечірній підсумок вимкнений (§6.2).
    public var cutoffWithoutEveningMinutes = 60
    public var rescueMinStreak = 3

    /// Типова порція: медіана за 14 днів, обмежена й округлена (§3.3).
    public var portionClamp = 150...500
    public var portionStep = 50
    public var portionHistoryDays = 14

    /// Горизонт плану: сьогодні + 2 дні, плюс дні повернення +3 і +7 від останньої дії (§16.2).
    public var horizonDays = 2
    public var comebackOffsets = [3, 7]

    /// Відкриття застосунку чи undo: перше нагадування — не раніше ніж через 30 хв (§6.2, «Скидання»).
    public var interactionDelayMinutes = 30
    /// «Нагадати за годину» (§6.4).
    public var snoozeDelayMinutes = 60

    /// iOS тримає не більше 64 запланованих на застосунок; запас — під відлуння, що
    /// додаються поза планом (§16.2).
    public var maxPending = 64
    public var echoReserve = 4
    /// Не планувати те, що настане за кілька секунд: календарний тригер у минулому iOS мовчки
    /// відкидає, а запит, що спрацював під час планування, лише плутає журнал.
    public var minLeadSeconds: TimeInterval = 5

    /// «Не зараз» у шторці дозволу — спитати ще раз через 3 дні (§16.5).
    public var permissionRepromptDays = 3
    /// Журнал потрібен для ротації текстів і звірки — довша історія не потрібна.
    public var logRetentionDays = 35

    public init() {}

    public func pace(for frequency: ReminderFrequency) -> Pace {
        pace[frequency] ?? Pace(k: 1.0, minGapMinutes: 60, maxGapMinutes: 180)
    }

    public static let `default` = NotificationRules()
}
