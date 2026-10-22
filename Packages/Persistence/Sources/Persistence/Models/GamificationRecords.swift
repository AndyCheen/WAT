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
    /// Не використовується з WAT-34: готова заморозка — це сам `RewardItem` в інвентарі.
    /// Поле лишається в схемі, щоб не ламати міграцію.
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

    // Параметри, зафіксовані у мить видачі (SPEC-QUESTS §4.7, §8). Типові значення — легка міграція: інстанси
    // до WAT-63 мають 0 / nil і беруть XP з архівного визначення.
    /// XP за виконання — перебалансування не змінює вже виданого.
    public var rewardXp: Int = 0
    /// `QuestDifficulty` (1…3); 0 — архівне, без складності.
    public var difficultyRaw: Int = 0
    /// T для «до T» і кінця блоку (хвилина доби). У тижневого Т8 — опорна медіана закриття норми: дедлайн
    /// кожного дня рахується з розкладу того дня.
    public var deadlineMinute: Int?
    /// Блок цілі частини доби (Д7, Н2) — індекс у `PaceCurve.goalBlocks()`.
    public var blockIndex: Int?
    /// N: склянок для Д6 / Д10, днів для тижневих.
    public var count: Int?
    /// День тижня для Н3: 0 — понеділок.
    public var weekdayIndex: Int?

    public init(
        id: UUID = UUID(),
        defKey: String,
        periodKey: String,
        target: Double,
        assignedAt: Date,
        expiresAt: Date? = nil,
        rewardXp: Int = 0,
        difficultyRaw: Int = 0,
        deadlineMinute: Int? = nil,
        blockIndex: Int? = nil,
        count: Int? = nil,
        weekdayIndex: Int? = nil
    ) {
        self.id = id
        self.defKey = defKey
        self.periodKey = periodKey
        self.target = target
        self.assignedAt = assignedAt
        self.expiresAt = expiresAt
        self.rewardXp = rewardXp
        self.difficultyRaw = difficultyRaw
        self.deadlineMinute = deadlineMinute
        self.blockIndex = blockIndex
        self.count = count
        self.weekdayIndex = weekdayIndex
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
    /// Відкриття відсвятковано вікном на весь екран (WAT-60, SPEC-ACHIEVEMENTS §8.5). Відкат його не скидає:
    /// зняте видаленою порцією й відкрите знову вдруге вікна не отримує.
    public var celebratedAt: Date?

    public init(defKey: String, target: Double) {
        self.defKey = defKey
        self.target = target
    }

    public var isUnlocked: Bool { unlockedAt != nil }
    public var fraction: Double { target > 0 ? min(1, value / target) : 0 }
}

/// Виданий приз (SPEC-PRIZES §9.1). Використані й прострочені записи не видаляються:
/// на них тримаються `XPEntry.refId`, метрика `prize.activated` і повернення заморозки.
@Model
public final class RewardItem {
    public var id: UUID = UUID()
    public var defKey: String = ""
    public var sourceRaw: Int = RewardSource.level.rawValue
    public var acquiredAt: Date = Date()
    public var activatedAt: Date?
    public var expiresAt: Date?
    public var stateRaw: Int = RewardItemState.ready.rawValue
    public var acquiredByRef: UUID?
    /// Крапка «нове» — окремо від стану, як в `AchievementProgress`.
    public var seenAt: Date?
    /// Який день заморожено — щоб повернути приз, якщо день усе ж закрили (§6.3).
    public var usedOnDayKey: String?

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
        get { RewardItemState(rawValue: stateRaw) ?? .ready }
        set { stateRaw = newValue.rawValue }
    }
}
