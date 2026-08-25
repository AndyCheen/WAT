import Foundation
import Core
import Persistence
import Metrics

/// Досягнення: прогрес, розблокування, відкат за політикою.
@MainActor
public final class AchievementEngine {
    private let store: GamificationStoreProtocol
    private let metrics: MetricsService

    public init(store: GamificationStoreProtocol, metrics: MetricsService) {
        self.store = store
        self.metrics = metrics
    }

    /// Створює рядки прогресу для всіх визначень каталогу.
    public func bootstrap() {
        for definition in AchievementCatalog.all where store.achievementProgress(defKey: definition.key) == nil {
            store.insertAchievement(AchievementProgress(defKey: definition.key, target: definition.target))
        }
        store.save()
    }

    @discardableResult
    public func evaluate(context: RuleContext, triggerRef: UUID?) -> [AchievementDefinition] {
        var unlocked: [AchievementDefinition] = []
        for definition in AchievementCatalog.all {
            let progress = store.achievementProgress(defKey: definition.key)
                ?? {
                    let created = AchievementProgress(defKey: definition.key, target: definition.target)
                    store.insertAchievement(created)
                    return created
                }()

            progress.target = definition.target
            progress.value = definition.rule.value(in: context)

            if progress.value >= definition.target, !progress.isUnlocked {
                progress.unlockedAt = context.date
                progress.unlockedByRef = triggerRef
                unlocked.append(definition)
                metrics.record(MetricEvent(
                    name: .achievementUnlocked, value: 1, occurredAt: context.date,
                    sourceRef: DeterministicID.uuid(from: "achievement:\(definition.key)"),
                    payload: ["key": definition.key]
                ))
            }
        }
        store.save()
        return unlocked
    }

    /// Знімає досягнення, якщо умова більше не виконується (RevertPolicy.full).
    /// Досягнення, яке лишається виконаним з інших даних, не чіпаємо.
    @discardableResult
    public func revert(context: RuleContext, sourceRef: UUID, policy: RevertPolicy, at date: Date) -> [String] {
        guard policy == .full else { return [] }
        var relocked: [String] = []

        for definition in AchievementCatalog.all {
            guard let progress = store.achievementProgress(defKey: definition.key), progress.isUnlocked else {
                continue
            }
            progress.value = definition.rule.value(in: context)
            if progress.value < definition.target {
                progress.unlockedAt = nil
                progress.unlockedByRef = nil
                progress.seenAt = nil
                relocked.append(definition.key)
                metrics.revert(
                    sourceRef: DeterministicID.uuid(from: "achievement:\(definition.key)"), at: date
                )
            }
        }
        store.save()
        return relocked
    }

    public func snapshots() -> [AchievementSnapshot] {
        AchievementCatalog.all.map { definition in
            let progress = store.achievementProgress(defKey: definition.key)
            return AchievementSnapshot(
                key: definition.key,
                title: definition.title,
                details: definition.details,
                emoji: definition.emoji,
                category: definition.category,
                value: progress?.value ?? 0,
                target: definition.target,
                isUnlocked: progress?.isUnlocked ?? false,
                isSecret: definition.isSecret
            )
        }
    }

    public func markAllSeen(at date: Date) {
        for progress in store.allAchievementProgress() where progress.isUnlocked && progress.seenAt == nil {
            progress.seenAt = date
        }
        store.save()
    }

    public var hasUnseenUnlocks: Bool {
        store.allAchievementProgress().contains { $0.isUnlocked && $0.seenAt == nil }
    }
}
