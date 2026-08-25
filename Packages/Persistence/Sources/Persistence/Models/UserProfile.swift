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
    public var notificationsEnabled: Bool = true
    public var localeIdentifier: String = "uk"

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
}
