import Foundation
import Core
import Persistence
import Metrics

/// Координатор гейміфікації: єдиний підписник шини метрик, який у детермінованому
/// порядку прокручує серії → завдання → досягнення → XP.
///
/// Модуль обліку води про нього не знає — звʼязок односторонній через `MetricsService`.
@MainActor
public final class GamificationService: MetricsSubscriber {
    private let store: GamificationStoreProtocol
    private let dayLogs: DayLogRepositoryProtocol
    private let profiles: ProfileRepositoryProtocol
    private let metrics: MetricsService
    private let calendar: CalendarService

    public let xp: XPEngine
    public let streaks: StreakEngine
    public let quests: QuestEngine
    public let achievements: AchievementEngine
    public var revertPolicy: RevertPolicy

    /// Захист від рекурсії: внутрішні події (XP, розблокування) не запускають новий цикл.
    private var isEvaluating = false

    public init(
        store: GamificationStoreProtocol,
        dayLogs: DayLogRepositoryProtocol,
        profiles: ProfileRepositoryProtocol,
        metrics: MetricsService,
        calendar: CalendarService,
        curve: LevelCurve = LinearLevelCurve(),
        rules: XPRules = .default,
        revertPolicy: RevertPolicy = .full
    ) {
        self.store = store
        self.dayLogs = dayLogs
        self.profiles = profiles
        self.metrics = metrics
        self.calendar = calendar
        self.revertPolicy = revertPolicy
        self.xp = XPEngine(store: store, metrics: metrics, calendar: calendar, curve: curve, rules: rules)
        self.streaks = StreakEngine(store: store, dayLogs: dayLogs, calendar: calendar)
        self.quests = QuestEngine(store: store, calendar: calendar)
        self.achievements = AchievementEngine(store: store, metrics: metrics)
    }

    /// Підписка на шину + початкова синхронізація стану.
    public func bootstrap() {
        achievements.bootstrap()
        xp.recalculateFromJournal(at: calendar.now)
        metrics.subscribe(self)
        refresh(at: calendar.now)
    }

    /// Повний перерахунок стану — на старті застосунку та при зміні доби.
    public func refresh(at date: Date) {
        grantLevelRewards(at: date)
        streaks.recompute(at: date)
        let context = makeContext(at: date)
        quests.ensureInstances(context: context, level: xp.progress().level)
        let completed = quests.evaluate(context: context, triggerRef: nil)
        awardQuestXP(completed, at: date)
        let unlocked = achievements.evaluate(context: makeContext(at: date), triggerRef: nil)
        awardAchievementXP(unlocked, at: date)
    }

    // MARK: - MetricsSubscriber

    public func metricsDidRecord(_ event: RecordedMetricEvent, service: MetricsService) {
        guard !Self.internalMetrics.contains(event.name), !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        let date = event.occurredAt

        if event.name == .dayGoalMet {
            streaks.recompute(at: date)
            publishStreakMetric(at: date)
        }

        let streak = streaks.summary().current
        if event.name == .intakeAdded {
            xp.award(
                amount: xp.rules.perIntake, reason: .intake,
                refId: event.sourceRef, at: date, streak: streak
            )
        }
        if event.name == .dayGoalMet {
            xp.award(amount: xp.rules.perDailyGoal, reason: .dailyGoal, refId: event.sourceRef, at: date)
        }

        let context = makeContext(at: date)
        quests.ensureInstances(context: context, level: xp.progress().level)
        let completed = quests.evaluate(context: context, triggerRef: event.sourceRef)
        awardQuestXP(completed, at: date)

        let unlocked = achievements.evaluate(context: makeContext(at: date), triggerRef: event.sourceRef)
        awardAchievementXP(unlocked, at: date)

        grantLevelRewards(at: date)
    }

    /// Кожен новий рівень кладе свої нагороди в інвентар призів (макет 3f).
    /// Дедуплікація — за детермінованим ключем, тому повторний виклик безпечний.
    @discardableResult
    public func grantLevelRewards(at date: Date) -> [RewardItem] {
        let level = xp.progress().level
        guard level > 1 else { return [] }

        let existing = Set(store.rewardItems().compactMap(\.acquiredByRef))
        var granted: [RewardItem] = []

        for lvl in 2...level {
            for definition in RewardCatalog.rewards(forLevel: lvl) {
                let ref = DeterministicID.uuid(from: "level:\(lvl):\(definition.key)")
                guard !existing.contains(ref) else { continue }
                let item = RewardItem(
                    defKey: definition.key, source: .level, acquiredAt: date, acquiredByRef: ref
                )
                store.insertReward(item)
                granted.append(item)
            }
        }
        if !granted.isEmpty { store.save() }
        return granted
    }

    public func metricsDidRevert(_ events: [RecordedMetricEvent], sourceRef: UUID, service: MetricsService) {
        guard !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        let date = events.first?.occurredAt ?? calendar.now
        // 1. Забираємо XP, нарахований саме цією дією.
        xp.revert(refId: sourceRef, at: date)
        // 2. Серія перераховується з денних логів — вона вже врахувала зміну.
        streaks.recompute(at: date)

        let context = makeContext(at: date)
        // 3. Завдання та досягнення знімаються, якщо умова більше не виконується.
        let reopened = quests.revert(context: context, sourceRef: sourceRef, policy: revertPolicy)
        for quest in reopened {
            xp.revert(refId: quest.id, at: date)
        }
        for key in achievements.revert(context: context, sourceRef: sourceRef, policy: revertPolicy, at: date) {
            xp.revert(refId: DeterministicID.uuid(from: "achievement:\(key)"), at: date)
        }
    }

    // MARK: - Знімки для UI

    public func levelProgress() -> LevelProgress { xp.progress() }
    public func streakSummary() -> StreakSummary { streaks.summary() }
    public func dailyQuests(at date: Date? = nil) -> [QuestSnapshot] {
        quests.snapshots(scope: .daily, at: date ?? calendar.now)
    }
    public func weeklyQuests(at date: Date? = nil) -> [QuestSnapshot] {
        quests.snapshots(scope: .weekly, at: date ?? calendar.now)
    }
    public func achievementSnapshots() -> [AchievementSnapshot] { achievements.snapshots() }
    public var hasUnseenAchievements: Bool { achievements.hasUnseenUnlocks }
    public func markAchievementsSeen() { achievements.markAllSeen(at: calendar.now) }

    /// Призи в інвентарі (макет 3f).
    public func prizes() -> [RewardSnapshot] {
        store.rewardItems().compactMap { item in
            guard let definition = RewardCatalog.definition(item.defKey) else { return nil }
            return RewardSnapshot(
                id: item.id, key: item.defKey, title: definition.title, details: definition.details,
                emoji: definition.emoji, kind: definition.kind, isActivated: item.activatedAt != nil
            )
        }
    }

    @discardableResult
    public func activatePrize(id: UUID, at date: Date? = nil) -> Bool {
        let now = date ?? calendar.now
        guard let item = store.rewardItems().first(where: { $0.id == id }), item.activatedAt == nil else {
            return false
        }
        item.activatedAt = now
        item.state = .active
        store.save()

        if item.defKey == "streak.freeze" {
            streaks.grantFreezeToken()
        }
        if item.defKey == "xp.streakBonus" {
            xp.award(amount: 50, reason: .prize, refId: item.id, at: now)
        }
        metrics.record(MetricEvent(
            name: .prizeActivated, value: 1, occurredAt: now, sourceRef: item.id,
            payload: ["key": item.defKey]
        ))
        return true
    }

    /// Нагороди за рівні — список для шторки «Нагороди за рівні» (макет 3f).
    public func levelRewards(upTo level: Int = 12) -> [LevelRewardSnapshot] {
        let current = xp.progress().level
        return (1...max(level, current + 4)).flatMap { lvl in
            RewardCatalog.rewards(forLevel: lvl).map { definition in
                LevelRewardSnapshot(
                    level: lvl, key: definition.key, title: definition.title,
                    details: definition.details, emoji: definition.emoji, isUnlocked: lvl <= current
                )
            }
        }
    }

    public func nextLevelRewards() -> (level: Int, rewards: [LevelRewardSnapshot]) {
        let next = xp.progress().level + 1
        let rewards = RewardCatalog.rewards(forLevel: next).map {
            LevelRewardSnapshot(
                level: next, key: $0.key, title: $0.title,
                details: $0.details, emoji: $0.emoji, isUnlocked: false
            )
        }
        return (next, rewards)
    }

    // MARK: - Внутрішнє

    private static let internalMetrics: Set<MetricKey> = [
        .xpEarned, .levelReached, .achievementUnlocked, .questCompleted, .streakCurrent, .prizeActivated
    ]

    private func makeContext(at date: Date) -> RuleContext {
        let streak = streaks.summary()
        return RuleContext(
            metrics: metrics,
            calendar: calendar,
            date: date,
            dailyGoalMl: profiles.currentGoalMl(on: calendar.dayKey(for: date)),
            currentStreak: streak.current,
            longestStreak: streak.longest
        )
    }

    private func publishStreakMetric(at date: Date) {
        let value = streaks.summary().current
        guard value > 0 else { return }
        let day = calendar.dayKey(for: date).rawValue
        metrics.record(MetricEvent(
            name: .streakCurrent, value: Double(value), occurredAt: date,
            sourceRef: DeterministicID.uuid(from: "streak:\(day):\(value)")
        ))
    }

    private func awardQuestXP(_ quests: [QuestInstance], at date: Date) {
        for quest in quests {
            guard let definition = QuestCatalog.definition(quest.defKey) else { continue }
            xp.award(amount: definition.rewardXp, reason: .questCompleted, refId: quest.id, at: date)
            metrics.record(MetricEvent(
                name: .questCompleted, value: 1, occurredAt: date, sourceRef: quest.id,
                payload: ["key": quest.defKey]
            ))
        }
    }

    private func awardAchievementXP(_ definitions: [AchievementDefinition], at date: Date) {
        for definition in definitions {
            xp.award(
                amount: definition.rewardXp, reason: .achievementUnlocked,
                refId: DeterministicID.uuid(from: "achievement:\(definition.key)"), at: date
            )
        }
    }
}
