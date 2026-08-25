import Foundation
import SwiftData
import Core

@MainActor
public protocol GamificationStoreProtocol: AnyObject {
    func levelState() -> LevelState
    func streakState() -> StreakState
    func insertXP(_ entry: XPEntry)
    func xpEntries(dayKey: String?) -> [XPEntry]
    func xpEntries(refId: UUID) -> [XPEntry]
    func totalXP() -> Int

    func quests(scope: QuestScope?, periodKey: String?) -> [QuestInstance]
    func quest(defKey: String, periodKey: String) -> QuestInstance?
    func insertQuest(_ quest: QuestInstance)

    func achievementProgress(defKey: String) -> AchievementProgress?
    func allAchievementProgress() -> [AchievementProgress]
    func insertAchievement(_ progress: AchievementProgress)

    func rewardItems() -> [RewardItem]
    func rewardItems(defKey: String) -> [RewardItem]
    func insertReward(_ item: RewardItem)
    func delete(_ item: RewardItem)
    func save()
}

@MainActor
public final class GamificationStore: GamificationStoreProtocol {
    private let context: ModelContext
    /// Ці рядки читаються по кілька разів на кожну дію користувача
    /// (правила, нарахування XP, серії), тому тримаємо посилання в памʼяті.
    private var cachedLevel: LevelState?
    private var cachedStreak: StreakState?
    private var achievementCache: [String: AchievementProgress] = [:]
    private var questCache: [String: QuestInstance] = [:]

    public init(context: ModelContext) {
        self.context = context
    }

    public func levelState() -> LevelState {
        if let cachedLevel { return cachedLevel }
        if let existing = (try? context.fetch(FetchDescriptor<LevelState>()))?.first {
            cachedLevel = existing
            return existing
        }
        let created = LevelState()
        context.insert(created)
        cachedLevel = created
        save()
        return created
    }

    public func streakState() -> StreakState {
        if let cachedStreak { return cachedStreak }
        if let existing = (try? context.fetch(FetchDescriptor<StreakState>()))?.first {
            cachedStreak = existing
            return existing
        }
        let created = StreakState()
        context.insert(created)
        cachedStreak = created
        save()
        return created
    }

    public func insertXP(_ entry: XPEntry) {
        context.insert(entry)
    }

    public func xpEntries(dayKey: String?) -> [XPEntry] {
        var descriptor = FetchDescriptor<XPEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let dayKey {
            descriptor.predicate = #Predicate { $0.dayKey == dayKey }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    public func xpEntries(refId: UUID) -> [XPEntry] {
        let descriptor = FetchDescriptor<XPEntry>(predicate: #Predicate { $0.refId == refId })
        return (try? context.fetch(descriptor)) ?? []
    }

    public func totalXP() -> Int {
        xpEntries(dayKey: nil).reduce(0) { $0 + $1.effectiveAmount }
    }

    public func quests(scope: QuestScope?, periodKey: String?) -> [QuestInstance] {
        var descriptor = FetchDescriptor<QuestInstance>(sortBy: [SortDescriptor(\.assignedAt)])
        if let periodKey {
            descriptor.predicate = #Predicate { $0.periodKey == periodKey }
        }
        let all = (try? context.fetch(descriptor)) ?? []
        guard let scope else { return all }
        // Скоуп зашитий у ключ періоду (день / тиждень), тому фільтруємо в памʼяті —
        // список активних квестів завжди короткий.
        return all.filter { instance in
            switch scope {
            case .daily: return instance.periodKey.count == 10
            case .weekly: return instance.periodKey.contains("-W")
            case .adhoc: return instance.periodKey.hasPrefix("adhoc")
            }
        }
    }

    public func quest(defKey: String, periodKey: String) -> QuestInstance? {
        let cacheKey = "\(defKey)|\(periodKey)"
        if let cached = questCache[cacheKey] { return cached }
        var descriptor = FetchDescriptor<QuestInstance>(
            predicate: #Predicate { $0.defKey == defKey && $0.periodKey == periodKey }
        )
        descriptor.fetchLimit = 1
        let found = (try? context.fetch(descriptor))?.first
        if let found { questCache[cacheKey] = found }
        return found
    }

    public func insertQuest(_ quest: QuestInstance) {
        context.insert(quest)
        questCache["\(quest.defKey)|\(quest.periodKey)"] = quest
    }

    public func achievementProgress(defKey: String) -> AchievementProgress? {
        if let cached = achievementCache[defKey] { return cached }
        var descriptor = FetchDescriptor<AchievementProgress>(predicate: #Predicate { $0.defKey == defKey })
        descriptor.fetchLimit = 1
        let found = (try? context.fetch(descriptor))?.first
        if let found { achievementCache[defKey] = found }
        return found
    }

    public func allAchievementProgress() -> [AchievementProgress] {
        (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
    }

    public func insertAchievement(_ progress: AchievementProgress) {
        context.insert(progress)
        achievementCache[progress.defKey] = progress
    }

    public func rewardItems() -> [RewardItem] {
        let descriptor = FetchDescriptor<RewardItem>(sortBy: [SortDescriptor(\.acquiredAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func rewardItems(defKey: String) -> [RewardItem] {
        let descriptor = FetchDescriptor<RewardItem>(predicate: #Predicate { $0.defKey == defKey })
        return (try? context.fetch(descriptor)) ?? []
    }

    public func insertReward(_ item: RewardItem) {
        context.insert(item)
    }

    public func delete(_ item: RewardItem) {
        context.delete(item)
    }

    public func save() {
        do { try context.save() } catch { AppLog.persistence.error("save: \(error)") }
    }
}
