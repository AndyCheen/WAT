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

/// Стан досягнення з погляду UI. Рахується в знімку, а не в екранах —
/// інакше три поверхні модуля (блок 3f, екран 2e, картка) розійдуться в правилі.
public enum AchievementState: Equatable, Sendable {
    /// Користувач іще не наближався: `value == 0`.
    case locked
    case inProgress
    case unlocked
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
    public let rewardXp: Int
    public let unlockedAt: Date?
    /// Відкрите, але ще не переглянуте — помаранчева крапка на бейджі й плитці.
    public let isNew: Bool

    public var id: String { key }

    public init(
        key: String, title: String, details: String, emoji: String,
        category: AchievementCategory, value: Double, target: Double,
        isUnlocked: Bool, isSecret: Bool,
        rewardXp: Int = 0, unlockedAt: Date? = nil, isNew: Bool = false
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
        self.rewardXp = rewardXp
        self.unlockedAt = unlockedAt
        self.isNew = isNew
    }

    public var fraction: Double { target > 0 ? min(1, value / target) : 0 }

    public var state: AchievementState {
        if isUnlocked { return .unlocked }
        return fraction > 0 ? .inProgress : .locked
    }

    /// «5/7» — компактний підпис під смугою плитки.
    public var progressLabel: String {
        isUnlocked ? "Готово" : "\(Int(min(value, target)))/\(Int(target))"
    }

    /// «5 / 7» — у картці деталей, де під числом є місце дихати.
    public var valueLabel: String { "\(Int(min(value, target))) / \(Int(target))" }
}

/// Зріз за станом — чипи на екрані 2e (SPEC-ACHIEVEMENTS §3.2).
public enum AchievementStateFilter: String, CaseIterable, Sendable {
    case all, inProgress, unlocked, locked

    public var title: String {
        switch self {
        case .all: return "Усі"
        case .inProgress: return "У процесі"
        case .unlocked: return "Відкриті"
        case .locked: return "Закриті"
        }
    }

    public func matches(_ item: AchievementSnapshot) -> Bool {
        switch self {
        case .all: return true
        case .inProgress: return item.state == .inProgress
        case .unlocked: return item.isUnlocked
        // «Закриті» — усе невідкрите, зокрема й те, що в процесі: чип відповідає
        // на «чого в мене ще немає», а не повторює «У процесі».
        case .locked: return !item.isUnlocked
        }
    }
}

/// Єдиний порядок досягнень для екрана 2e і блоку 3f (SPEC-ACHIEVEMENTS §3.4).
///
/// Екран має відповідати на «що я можу взяти наступним», а не бути вітриною минулого:
/// щойно відкриті → найближчі до розблокування → решта відкритих → не розпочаті.
extension Collection where Element == AchievementSnapshot {
    public var sortedForDisplay: [AchievementSnapshot] {
        func group(_ item: AchievementSnapshot) -> Int {
            if item.isNew { return 0 }
            switch item.state {
            case .inProgress: return 1
            case .unlocked: return 2
            case .locked: return 3
            }
        }
        return enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (lhs.element, rhs.element)
                let (gl, gr) = (group(l), group(r))
                if gl != gr { return gl < gr }
                switch gl {
                case 0, 2:
                    let (dl, dr) = (l.unlockedAt ?? .distantPast, r.unlockedAt ?? .distantPast)
                    if dl != dr { return dl > dr }
                case 1:
                    if l.fraction != r.fraction { return l.fraction > r.fraction }
                default:
                    break
                }
                // Рівні ключі сортування лишаються в порядку каталогу — сітка не «тасується».
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Вітрина блоку 3f: лише відкриті й ті, що в процесі, не більше двох рядів по 4.
    /// Нульовий прогрес не показуємо ніколи — на 3f немає місця пояснювати сірий кружечок.
    public var showcase: [AchievementSnapshot] {
        Array(sortedForDisplay.filter { $0.state != .locked }.prefix(AchievementCatalog.showcaseLimit))
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
