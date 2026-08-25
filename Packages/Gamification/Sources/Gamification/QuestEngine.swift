import Foundation
import Core
import Persistence
import Metrics

/// Щоденні та тижневі завдання: видача інстансів, прогрес, закриття й відкат.
@MainActor
public final class QuestEngine {
    private let store: GamificationStoreProtocol
    private let calendar: CalendarService

    public init(store: GamificationStoreProtocol, calendar: CalendarService) {
        self.store = store
        self.calendar = calendar
    }

    /// Створює інстанси завдань на поточний день і тиждень, якщо їх ще немає.
    public func ensureInstances(context: RuleContext, level: Int) {
        let dayKey = calendar.dayKey(for: context.date).rawValue
        let weekKey = calendar.weekKey(for: context.date).rawValue

        let dailyPool = QuestCatalog.daily.filter { $0.minLevel <= level }
        for definition in dailyPool.prefix(QuestCatalog.dailySlots) {
            ensure(definition, periodKey: dayKey, context: context)
        }
        for definition in QuestCatalog.weekly where definition.minLevel <= level {
            ensure(definition, periodKey: weekKey, context: context)
        }
    }

    private func ensure(_ definition: QuestDefinition, periodKey: String, context: RuleContext) {
        let target = definition.target.resolve(dailyGoalMl: context.dailyGoalMl)
        if let existing = store.quest(defKey: definition.key, periodKey: periodKey) {
            // Норму могли змінити протягом дня — ціль завдання йде за нею.
            if existing.target != target, case .fixed = definition.target {} else {
                existing.target = target
            }
            return
        }
        let instance = QuestInstance(
            defKey: definition.key,
            periodKey: periodKey,
            target: target,
            assignedAt: context.date
        )
        store.insertQuest(instance)
        store.save()
    }

    /// Перераховує прогрес усіх активних завдань.
    /// Повертає ті, що щойно закрилися — на них нараховується XP.
    @discardableResult
    public func evaluate(context: RuleContext, triggerRef: UUID?) -> [QuestInstance] {
        let dayKey = calendar.dayKey(for: context.date).rawValue
        let weekKey = calendar.weekKey(for: context.date).rawValue
        let instances = store.quests(scope: nil, periodKey: dayKey) + store.quests(scope: nil, periodKey: weekKey)

        var justCompleted: [QuestInstance] = []
        for instance in instances {
            guard let definition = QuestCatalog.definition(instance.defKey) else { continue }
            instance.progress = definition.rule.value(in: context)

            if instance.progress >= instance.target, instance.state == .active {
                instance.state = .completed
                instance.completedAt = context.date
                instance.completedByRef = triggerRef
                justCompleted.append(instance)
            }
        }
        store.save()
        return justCompleted
    }

    /// Відкат: якщо умова більше не виконується, завдання повертається в активні.
    @discardableResult
    public func revert(context: RuleContext, sourceRef: UUID, policy: RevertPolicy) -> [QuestInstance] {
        guard policy == .full else { return [] }
        let dayKey = calendar.dayKey(for: context.date).rawValue
        let weekKey = calendar.weekKey(for: context.date).rawValue
        let instances = store.quests(scope: nil, periodKey: dayKey) + store.quests(scope: nil, periodKey: weekKey)

        var reopened: [QuestInstance] = []
        for instance in instances {
            guard let definition = QuestCatalog.definition(instance.defKey) else { continue }
            instance.progress = definition.rule.value(in: context)
            if instance.isDone, instance.progress < instance.target {
                instance.state = .active
                instance.completedAt = nil
                instance.completedByRef = nil
                reopened.append(instance)
            }
        }
        store.save()
        return reopened
    }

    public func snapshots(scope: QuestScope, at date: Date) -> [QuestSnapshot] {
        let periodKey = scope == .weekly
            ? calendar.weekKey(for: date).rawValue
            : calendar.dayKey(for: date).rawValue

        return store.quests(scope: nil, periodKey: periodKey).compactMap { instance in
            guard let definition = QuestCatalog.definition(instance.defKey), definition.scope == scope else {
                return nil
            }
            return QuestSnapshot(
                id: instance.id,
                key: instance.defKey,
                title: definition.title,
                scope: definition.scope,
                progress: instance.progress,
                target: instance.target,
                isDone: instance.isDone,
                rewardXp: definition.rewardXp
            )
        }
    }
}
