import Foundation
import SwiftData

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

    public var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRaw) ?? .system }
        set { themeModeRaw = newValue.rawValue }
    }

    public static let glassRange = 100...500
    public static let glassStep = 25
}
