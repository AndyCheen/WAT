import Foundation
import SwiftData

/// Журнал досвіду. Рівень — похідна від журналу, тому відкат дії чесно повертає XP.
@Model
public final class XPEntry {
    public var id: UUID = UUID()
    public var amount: Int = 0
    public var multiplier: Double = 1
    public var reasonRaw: Int = XPReason.intake.rawValue
    public var refId: UUID?
    public var dayKey: String = ""
    public var createdAt: Date = Date()
    public var revertedAt: Date?

    public init(
        id: UUID = UUID(),
        amount: Int,
        multiplier: Double = 1,
        reason: XPReason,
        refId: UUID? = nil,
        dayKey: String,
        createdAt: Date
    ) {
        self.id = id
        self.amount = amount
        self.multiplier = multiplier
        self.reasonRaw = reason.rawValue
        self.refId = refId
        self.dayKey = dayKey
        self.createdAt = createdAt
    }

    public var reason: XPReason { XPReason(rawValue: reasonRaw) ?? .intake }
    public var effectiveAmount: Int { revertedAt == nil ? Int((Double(amount) * multiplier).rounded()) : 0 }
}

/// Кеш рівня — щоб не перечитувати весь журнал на кожен рендер.
@Model
public final class LevelState {
    public var level: Int = 1
    public var totalXp: Int = 0
    public var xpIntoLevel: Int = 0
    public var xpForNextLevel: Int = 100
    public var updatedAt: Date = Date()

    public init() {}
}

@Model
public final class StreakState {
    public var currentStreak: Int = 0
    public var longestStreak: Int = 0
    public var lastCountedDayKey: String?
    public var freezeTokens: Int = 0
    public var lastFreezeUsedDayKey: String?
    public var frozenDayKeys: [String] = []
    public var updatedAt: Date = Date()

    public init() {}
}

@Model
public final class QuestInstance {
    public var id: UUID = UUID()
    public var defKey: String = ""
    public var periodKey: String = ""
    public var target: Double = 1
    public var progress: Double = 0
    public var stateRaw: Int = QuestState.active.rawValue
    public var assignedAt: Date = Date()
    public var expiresAt: Date?
    public var completedAt: Date?
    public var completedByRef: UUID?

    public init(
        id: UUID = UUID(),
        defKey: String,
        periodKey: String,
        target: Double,
        assignedAt: Date,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.defKey = defKey
        self.periodKey = periodKey
        self.target = target
        self.assignedAt = assignedAt
        self.expiresAt = expiresAt
    }

    public var state: QuestState {
        get { QuestState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    public var isDone: Bool { state == .completed || state == .claimed }
    public var progressFraction: Double { target > 0 ? min(1, progress / target) : 0 }
}

@Model
public final class AchievementProgress {
    @Attribute(.unique) public var defKey: String = ""
    public var value: Double = 0
    public var target: Double = 1
    public var unlockedAt: Date?
    public var unlockedByRef: UUID?
    public var seenAt: Date?

    public init(defKey: String, target: Double) {
        self.defKey = defKey
        self.target = target
    }

    public var isUnlocked: Bool { unlockedAt != nil }
    public var fraction: Double { target > 0 ? min(1, value / target) : 0 }
}

/// Видана нагорода або приз (у т. ч. «заморозка серії»).
@Model
public final class RewardItem {
    public var id: UUID = UUID()
    public var defKey: String = ""
    public var sourceRaw: Int = RewardSource.level.rawValue
    public var acquiredAt: Date = Date()
    public var activatedAt: Date?
    public var expiresAt: Date?
    public var stateRaw: Int = RewardItemState.new.rawValue
    public var acquiredByRef: UUID?

    public init(
        id: UUID = UUID(),
        defKey: String,
        source: RewardSource,
        acquiredAt: Date,
        acquiredByRef: UUID? = nil
    ) {
        self.id = id
        self.defKey = defKey
        self.sourceRaw = source.rawValue
        self.acquiredAt = acquiredAt
        self.acquiredByRef = acquiredByRef
    }

    public var source: RewardSource { RewardSource(rawValue: sourceRaw) ?? .level }
    public var state: RewardItemState {
        get { RewardItemState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }
}
