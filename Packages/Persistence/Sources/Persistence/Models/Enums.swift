import Foundation

/// Джерело порції — знадобиться для аналітики «скільки додано з віджета» (ТЗ §2).
public enum IntakeSource: Int, Codable, CaseIterable, Sendable {
    case app = 0, widget, notification, siri, shortcut, seed
}

public enum GoalSource: Int, Codable, Sendable {
    case calculated = 0, manual, onboarding, seed
}

public enum ThemeMode: Int, Codable, CaseIterable, Sendable {
    case system = 0, light, dark
}

public enum Gender: Int, Codable, CaseIterable, Sendable {
    case unspecified = 0, male, female
}

public enum ActivityLevel: Int, Codable, CaseIterable, Sendable {
    case low = 0, medium, high

    public var title: String {
        switch self {
        case .low: return "Низька"
        case .medium: return "Середня"
        case .high: return "Висока"
        }
    }
}

public enum ClimateLevel: Int, Codable, CaseIterable, Sendable {
    case moderate = 0, hot

    public var title: String {
        switch self {
        case .moderate: return "Помірний"
        case .hot: return "Спекотний"
        }
    }
}

public enum XPReason: Int, Codable, Sendable {
    case intake = 0, questCompleted, achievementUnlocked, dailyGoal, dayPartGoal, prize, streakBonus, levelBonus
}

public enum QuestScope: Int, Codable, CaseIterable, Sendable {
    case daily = 0, weekly, adhoc
}

public enum QuestState: Int, Codable, Sendable {
    case active = 0, completed, expired, claimed
}

public enum RewardKind: Int, Codable, CaseIterable, Sendable {
    case theme = 0, xpBonus, streakFreeze, questType, badge
}

public enum RewardSource: Int, Codable, Sendable {
    case level = 0, quest, achievement, random, seed
}

public enum RewardItemState: Int, Codable, Sendable {
    case new = 0, active, used, expired
}

public enum AchievementCategory: Int, Codable, CaseIterable, Sendable {
    case general = 0, streak, volume, secret

    public var title: String {
        switch self {
        case .general: return "Всі"
        case .streak: return "Стріки"
        case .volume: return "Обʼєм"
        case .secret: return "Секретні"
        }
    }
}

public enum MetricPeriodType: Int, Codable, CaseIterable, Sendable {
    case day = 0, week, month, year, all
}

public enum NotificationKind: Int, Codable, CaseIterable, Sendable {
    case smart = 0, fixed, adaptive, analysis
}
