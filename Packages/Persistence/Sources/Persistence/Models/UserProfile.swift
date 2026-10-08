import Foundation
import SwiftData
import Core

/// Єдиний рядок з налаштуваннями користувача.
@Model
public final class UserProfile {
    public var createdAt: Date = Date()
    public var genderRaw: Int = Gender.unspecified.rawValue
    public var birthYear: Int?
    public var weightKg: Double?
    public var activityRaw: Int = ActivityLevel.medium.rawValue
    public var climateRaw: Int = ClimateLevel.moderate.rawValue
    public var volumeUnitRaw: Int = 0
    public var massUnitRaw: Int = 0
    public var themeModeRaw: Int = ThemeMode.system.rawValue
    public var onboardingCompleted: Bool = false
    public var hapticsEnabled: Bool = true
    public var soundEnabled: Bool = true
    /// Головний вимикач сповіщень (SPEC-NOTIFICATIONS §15.1).
    public var notificationsEnabled: Bool = true
    public var localeIdentifier: String = "uk"

    // Режим дня — у профілі, а не в налаштуваннях сповіщень: з нього ж рахується крива
    // темпу, і згодом його питатиме онбординг (SPEC-NOTIFICATIONS §15.1, §21).
    // Хвилини від 00:00; відбій не пізніше 24:00 — доба застосунку закінчується опівночі (§16.6).
    public var wakeMinutes: Int = 8 * 60
    public var sleepMinutes: Int = 22 * 60
    public var weekendScheduleEnabled: Bool = false
    public var weekendWakeMinutes: Int = 9 * 60
    public var weekendSleepMinutes: Int = 23 * 60
    /// «Моя склянка» — об'єм для дії «+склянка» й ранкової склянки (§7.1, п. 5).
    public var glassMl: Int = 250
    /// Чи вже відповіли на «Скільки в твоїй склянці?» (§7.1, п. 5): вікно «Склянка» питає
    /// один раз. Зміна склянки на екрані «Сповіщення» — теж відповідь.
    public var glassConfirmed: Bool = false
    /// Останній об'єм, доданий через шторку «Інше» (WAT-45): з нього вона й відкривається —
    /// нестандартні порції в людей зазвичай ті самі. `nil` — шторкою ще не користувались.
    public var lastCustomAmountMl: Int?

    /// «Ритм дня» (WAT-42, SPEC-NOTIFICATIONS §28): вимкнено — режим «просто норма за день», без цілей
    /// частин доби в чекпоінтах, XP, завданнях, звітах і на головному. Тут, а не в `NotificationSettings`:
    /// перемикач стосується гри й звітів, а не лише сповіщень.
    public var dayRhythmEnabled: Bool = true

    // Пропозиція змінити графік (WAT-41, SPEC-NOTIFICATIONS §27): коли вікно показали востаннє, чим
    // закінчилось і наскільки великий був зсув — для правила «Ні — не питати 60 днів, якщо зсув не виріс».
    // Показ одразу пишеться як «закрили без відповіді»: застосунок могли вбити з відкритим вікном.
    public var scheduleOfferShownAt: Date?
    public var scheduleOfferOutcomeRaw: Int = ScheduleOfferOutcome.none.rawValue
    public var scheduleOfferShiftMinutes: Int = 0

    public init(createdAt: Date = Date()) {
        self.createdAt = createdAt
    }

    public var gender: Gender {
        get { Gender(rawValue: genderRaw) ?? .unspecified }
        set { genderRaw = newValue.rawValue }
    }

    public var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .medium }
        set { activityRaw = newValue.rawValue }
    }

    public var climate: ClimateLevel {
        get { ClimateLevel(rawValue: climateRaw) ?? .moderate }
        set { climateRaw = newValue.rawValue }
    }

    /// Система об'єму (WAT-46). Змінювати — через `HydrationService.setVolumeUnit(_:)`: він же
    /// переводить кнопки порцій на сітку нової системи.
    public var volumeUnit: VolumeUnit {
        get { VolumeUnit(rawValue: volumeUnitRaw) ?? .milliliters }
        set { volumeUnitRaw = newValue.rawValue }
    }

    public var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .system }
        set { themeModeRaw = newValue.rawValue }
    }

    public var scheduleOfferOutcome: ScheduleOfferOutcome {
        get { ScheduleOfferOutcome(rawValue: scheduleOfferOutcomeRaw) ?? .none }
        set { scheduleOfferOutcomeRaw = newValue.rawValue }
    }

    /// Розклад тижня одним значенням — для пропозиції графіка й її застосування.
    public var weekSchedule: WeekSchedule {
        get {
            WeekSchedule(
                weekday: DaySchedule(wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes),
                weekendEnabled: weekendScheduleEnabled,
                weekend: DaySchedule(wakeMinutes: weekendWakeMinutes, sleepMinutes: weekendSleepMinutes)
            )
        }
        set {
            wakeMinutes = newValue.weekday.wakeMinutes
            sleepMinutes = newValue.weekday.sleepMinutes
            weekendScheduleEnabled = newValue.weekendEnabled
            weekendWakeMinutes = newValue.weekend.wakeMinutes
            weekendSleepMinutes = newValue.weekend.sleepMinutes
        }
    }

    /// Розклад дня: у суботу й неділю — окремий, якщо його увімкнено.
    public func schedule(isWeekend: Bool) -> DaySchedule {
        weekSchedule.schedule(isWeekend: isWeekend)
    }

    /// Розклад конкретного дня: знімок із запису дня, а для днів без нього — поточний профіль.
    /// Єдиний шлях для XP частин доби, звіту й графіків, інакше вони розійдуться на старих днях.
    public func schedule(for log: DayLog?, isWeekend: Bool) -> DaySchedule {
        log?.scheduleSnapshot ?? schedule(isWeekend: isWeekend)
    }

    public static let glassRange = 100...500
    public static let glassStep = 25
}
