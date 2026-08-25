import Foundation
import Core
import Persistence
import Metrics

// MARK: - Завдання

/// Ціль завдання: фіксована або привʼязана до денної норми.
public enum QuestTarget: Sendable {
    case fixed(Double)
    case dailyGoal
    case dailyGoalFraction(Double)

    @MainActor
    public func resolve(dailyGoalMl: Int) -> Double {
        switch self {
        case .fixed(let value): return value
        case .dailyGoal: return Double(dailyGoalMl)
        case .dailyGoalFraction(let f): return Double(dailyGoalMl) * f
        }
    }
}

public struct QuestDefinition: Sendable, Identifiable {
    public let key: String
    public let scope: QuestScope
    public let title: String
    public let rule: MetricRule
    public let target: QuestTarget
    public let rewardXp: Int
    public let minLevel: Int

    public var id: String { key }

    public init(
        key: String,
        scope: QuestScope,
        title: String,
        rule: MetricRule,
        target: QuestTarget,
        rewardXp: Int,
        minLevel: Int = 1
    ) {
        self.key = key
        self.scope = scope
        self.title = title
        self.rule = rule
        self.target = target
        self.rewardXp = rewardXp
        self.minLevel = minLevel
    }
}

public enum QuestCatalog {
    /// Щоденні (макет 1a і 3f: «Випити 2 л води», «Додати 4 записи»).
    public static let daily: [QuestDefinition] = [
        QuestDefinition(
            key: "daily.goal",
            scope: .daily,
            title: "Випити денну норму",
            rule: MetricRule(key: .intakeAdded, period: .day, aggregate: .sum),
            target: .dailyGoal,
            rewardXp: 25
        ),
        QuestDefinition(
            key: "daily.entries4",
            scope: .daily,
            title: "Додати 4 записи",
            rule: MetricRule(key: .intakeCount, period: .day, aggregate: .sum),
            target: .fixed(4),
            rewardXp: 25
        ),
        QuestDefinition(
            key: "daily.morning",
            scope: .daily,
            title: "Випити воду зранку",
            rule: MetricRule(key: .partMorning, period: .day, aggregate: .sum),
            target: .fixed(200),
            rewardXp: 25
        )
    ]

    /// Тижневі (макет 3f: «Стрік 7 днів поспіль», «Випити норму 5 днів»).
    public static let weekly: [QuestDefinition] = [
        QuestDefinition(
            key: "weekly.streak7",
            scope: .weekly,
            title: "Стрік 7 днів поспіль",
            rule: .currentStreak,
            target: .fixed(7),
            rewardXp: 100
        ),
        QuestDefinition(
            key: "weekly.goal5days",
            scope: .weekly,
            title: "Випити норму 5 днів",
            rule: MetricRule(key: .dayGoalMet, period: .week, aggregate: .sum),
            target: .fixed(5),
            rewardXp: 100
        )
    ]

    public static let all: [QuestDefinition] = daily + weekly

    public static func definition(_ key: String) -> QuestDefinition? {
        all.first { $0.key == key }
    }

    /// Скільки щоденних завдань показуємо одночасно (макети показують два).
    public static let dailySlots = 2
}

// MARK: - Досягнення

public struct AchievementDefinition: Sendable, Identifiable {
    public let key: String
    public let title: String
    public let details: String
    public let emoji: String
    public let category: AchievementCategory
    public let rule: MetricRule
    public let target: Double
    public let rewardXp: Int
    public let isSecret: Bool

    public var id: String { key }

    public init(
        key: String,
        title: String,
        details: String,
        emoji: String,
        category: AchievementCategory,
        rule: MetricRule,
        target: Double,
        rewardXp: Int,
        isSecret: Bool = false
    ) {
        self.key = key
        self.title = title
        self.details = details
        self.emoji = emoji
        self.category = category
        self.rule = rule
        self.target = target
        self.rewardXp = rewardXp
        self.isSecret = isSecret
    }
}

/// Каталог 1:1 з макетами 1a / 2e / 3f.
public enum AchievementCatalog {
    public static let all: [AchievementDefinition] = [
        AchievementDefinition(
            key: "first.drop", title: "Перша крапля", details: "Перший запис води", emoji: "💧",
            category: .general,
            rule: MetricRule(key: .intakeCount, period: .all, aggregate: .sum),
            target: 1, rewardXp: 25
        ),
        AchievementDefinition(
            key: "day.goal", title: "Ціль дня", details: "Випито денну норму", emoji: "🎯",
            category: .volume,
            rule: MetricRule(key: .dayGoalMet, period: .all, aggregate: .sum),
            target: 1, rewardXp: 50
        ),
        AchievementDefinition(
            key: "streak.3", title: "3 дні поспіль", details: "Стрік 3+ днів", emoji: "🔥",
            category: .streak,
            rule: .longestStreak,
            target: 3, rewardXp: 50
        ),
        AchievementDefinition(
            key: "streak.7", title: "Тиждень поспіль", details: "Стрік 7+ днів", emoji: "⭐",
            category: .streak,
            rule: .longestStreak,
            target: 7, rewardXp: 100
        ),
        AchievementDefinition(
            key: "streak.30", title: "Місяць витримки", details: "Стрік 30 днів", emoji: "🏆",
            category: .streak,
            rule: .longestStreak,
            target: 30, rewardXp: 300
        ),
        AchievementDefinition(
            key: "big.gulp", title: "Великий ковток", details: "1 л за один раз", emoji: "🥤",
            category: .volume,
            rule: MetricRule(key: .intakeAdded, period: .all, aggregate: .max),
            target: 1000, rewardXp: 50
        ),
        AchievementDefinition(
            key: "marathon", title: "Марафонець", details: "20+ виконаних днів", emoji: "📅",
            category: .general,
            rule: MetricRule(key: .dayGoalMet, period: .all, aggregate: .sum),
            target: 20, rewardXp: 200
        )
    ]

    public static func definition(_ key: String) -> AchievementDefinition? {
        all.first { $0.key == key }
    }

    /// Категорії для табів екрана 2e — «Всі» плюс ті, що реально є в каталозі.
    public static var categories: [AchievementCategory] {
        var result: [AchievementCategory] = [.general]
        for category in [AchievementCategory.streak, .volume, .secret]
        where all.contains(where: { $0.category == category }) {
            result.append(category)
        }
        return result
    }
}

// MARK: - Нагороди

public struct RewardDefinition: Sendable, Identifiable {
    public let key: String
    public let kind: RewardKind
    public let title: String
    public let details: String
    public let emoji: String

    public var id: String { key }

    public init(key: String, kind: RewardKind, title: String, details: String, emoji: String) {
        self.key = key
        self.kind = kind
        self.title = title
        self.details = details
        self.emoji = emoji
    }
}

/// Нагороди за рівні — послідовність з макета 3f.
public enum RewardCatalog {
    public static let all: [RewardDefinition] = [
        RewardDefinition(key: "badge.hydration", kind: .badge, title: "Новий бейдж",
                         details: "«Знавець гідратації»", emoji: "🎖️"),
        RewardDefinition(key: "quests.weekly", kind: .questType, title: "Новий тип завдань",
                         details: "Щотижневі виклики", emoji: "🧩"),
        RewardDefinition(key: "theme.ocean", kind: .theme, title: "Приз",
                         details: "Ексклюзивна тема оформлення", emoji: "🎁"),
        RewardDefinition(key: "xp.streakBonus", kind: .xpBonus, title: "Бонус XP",
                         details: "+50 XP за щоденний стрік", emoji: "🌟"),
        RewardDefinition(key: "streak.freeze", kind: .streakFreeze, title: "Заморозка серії",
                         details: "Пропустити день без втрати серії", emoji: "🧊")
    ]

    public static func definition(_ key: String) -> RewardDefinition? {
        all.first { $0.key == key }
    }

    /// Яка нагорода видається на кожному рівні (макет 3f циклічно повторює 4 типи,
    /// а кожен 5-й рівень додає заморозку серії).
    public static func rewards(forLevel level: Int) -> [RewardDefinition] {
        let cycle = Array(all.prefix(4))
        var result = [cycle[(max(1, level) - 1) % cycle.count]]
        if level % 5 == 0, let freeze = definition("streak.freeze") {
            result.append(freeze)
        }
        return result
    }
}
