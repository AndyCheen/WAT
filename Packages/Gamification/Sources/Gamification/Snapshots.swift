import Foundation
import Core
import Persistence

/// Незмінні знімки для UI — екрани не працюють з `@Model` напряму.

public struct StreakSummary: Equatable, Sendable {
    public let current: Int
    public let longest: Int
    public let freezeTokens: Int
    public let lastCountedDay: DayKey?

    public init(current: Int, longest: Int, freezeTokens: Int, lastCountedDay: DayKey?) {
        self.current = current
        self.longest = longest
        self.freezeTokens = freezeTokens
        self.lastCountedDay = lastCountedDay
    }

    public static let empty = StreakSummary(current: 0, longest: 0, freezeTokens: 0, lastCountedDay: nil)
}

public struct QuestSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let title: String
    public let scope: QuestScope
    public let progress: Double
    public let target: Double
    public let isDone: Bool
    public let rewardXp: Int

    public init(
        id: UUID, key: String, title: String, scope: QuestScope,
        progress: Double, target: Double, isDone: Bool, rewardXp: Int
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.scope = scope
        self.progress = progress
        self.target = target
        self.isDone = isDone
        self.rewardXp = rewardXp
    }

    /// «Готово» або «3/4» — формат з макетів 1a і 3f.
    public var progressLabel: String {
        if isDone { return "Готово" }
        if target >= 1000 {
            return "\(Int((progress / target * 100).rounded()))%"
        }
        return "\(Int(min(progress, target)))/\(Int(target))"
    }

    public var fraction: Double { target > 0 ? min(1, progress / target) : 0 }
}

/// Розріз списку квестів на активні й виконані.
///
/// Живе тут, а не в екранах: приховування виконаних завдань потрібне і головному
/// екрану, і «Прогресу», а два однакові `filter` розʼїжджаються при першій же зміні правила.
extension Collection where Element == QuestSnapshot {
    /// Ще не виконані — те, що показуємо за замовчуванням.
    public var active: [QuestSnapshot] { filter { !$0.isDone } }
    public var completed: [QuestSnapshot] { filter(\.isDone) }
}

public struct AchievementSnapshot: Equatable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let details: String
    public let emoji: String
    public let category: AchievementCategory
    public let value: Double
    public let target: Double
    public let isUnlocked: Bool
    public let isSecret: Bool

    public var id: String { key }

    public init(
        key: String, title: String, details: String, emoji: String,
        category: AchievementCategory, value: Double, target: Double,
        isUnlocked: Bool, isSecret: Bool
    ) {
        self.key = key
        self.title = title
        self.details = details
        self.emoji = emoji
        self.category = category
        self.value = value
        self.target = target
        self.isUnlocked = isUnlocked
        self.isSecret = isSecret
    }

    public var fraction: Double { target > 0 ? min(1, value / target) : 0 }
    public var progressLabel: String {
        isUnlocked ? "Готово" : "\(Int(min(value, target)))/\(Int(target))"
    }
}

public struct RewardSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let title: String
    public let details: String
    public let emoji: String
    public let kind: RewardKind
    public let isActivated: Bool

    public init(
        id: UUID, key: String, title: String, details: String,
        emoji: String, kind: RewardKind, isActivated: Bool
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.details = details
        self.emoji = emoji
        self.kind = kind
        self.isActivated = isActivated
    }
}

public struct LevelRewardSnapshot: Equatable, Identifiable, Sendable {
    public let level: Int
    public let key: String
    public let title: String
    public let details: String
    public let emoji: String
    public let isUnlocked: Bool

    public var id: String { "\(level).\(key)" }

    public init(level: Int, key: String, title: String, details: String, emoji: String, isUnlocked: Bool) {
        self.level = level
        self.key = key
        self.title = title
        self.details = details
        self.emoji = emoji
        self.isUnlocked = isUnlocked
    }
}
