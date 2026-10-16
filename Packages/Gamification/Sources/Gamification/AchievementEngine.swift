import Foundation
import Core
import Persistence
import Metrics

/// Досягнення: прогрес, розблокування, відкат за політикою, знімки для UI.
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

    /// Прохід по каталогу. Відкрите вже не перераховується: досягнення не забирається інакше як відкатом,
    /// а правил сотня — і кожна порція ганяє їх 3–4 рази (`PerformanceTests`).
    ///
    /// Досягнення, що залежать від вимкненої функції, не рахуються зовсім — ні прогрес, ні розблокування
    /// (рішення від 15.10.2026, §4.4).
    func evaluate(_ inputs: AchievementInputs, triggerRef: UUID?) -> [AchievementDefinition] {
        var unlocked: [AchievementDefinition] = []
        var counts = collectionCounts()

        for definition in AchievementCatalog.evaluationOrder where inputs.gates.isOpen(definition.gate) {
            let progress = progress(for: definition)
            guard !progress.isUnlocked else { continue }
            let value = value(of: definition.rule, inputs, counts: counts)
            if progress.value != value { progress.value = value }
            if progress.target != definition.target { progress.target = definition.target }
            guard value >= definition.target else { continue }

            progress.unlockedAt = inputs.rules.date
            progress.unlockedByRef = triggerRef
            unlocked.append(definition)
            counts.all += 1
            if Self.countsTowardCore(definition) { counts.core += 1 }
            metrics.record(MetricEvent(
                name: .achievementUnlocked, value: 1, occurredAt: inputs.rules.date,
                sourceRef: Self.ref(definition.key), payload: ["key": definition.key]
            ))
        }
        // Без `save()`: прохід — частина дії, і її зберігає `metrics.commit()` (один раз на дію, CLAUDE.md).
        return unlocked
    }

    /// Знімає досягнення, якщо умова більше не виконується (`RevertPolicy.full`). Досягнення, яке
    /// лишається виконаним з інших даних, не чіпаємо. Залежне від вимкненої функції — теж: відкрите
    /// не забирається (§4.4).
    func revert(_ inputs: AchievementInputs, policy: RevertPolicy, at date: Date) -> [String] {
        guard policy == .full else { return [] }
        var relocked: [String] = []
        var counts = collectionCounts()

        // Колекції — останніми: вони бачать уже зняте в цьому проході.
        for definition in AchievementCatalog.evaluationOrder where inputs.gates.isOpen(definition.gate) {
            guard let progress = store.achievementProgress(defKey: definition.key), progress.isUnlocked else {
                continue
            }
            let towardCore = Self.countsTowardCore(definition)
            // Колекція рахує відкрите без себе самої.
            let own = definition.rule.isCollection
                ? (all: counts.all - 1, core: counts.core - (towardCore ? 1 : 0))
                : counts
            let value = value(of: definition.rule, inputs, counts: own)
            guard value < definition.target else { continue }

            progress.value = value
            progress.unlockedAt = nil
            progress.unlockedByRef = nil
            progress.seenAt = nil
            relocked.append(definition.key)
            counts.all -= 1
            if towardCore { counts.core -= 1 }
            metrics.revert(sourceRef: Self.ref(definition.key), at: date)
        }
        return relocked
    }

    /// Знімки для UI. Маскування — тут, а не у в'юсі (SPEC-ACHIEVEMENTS §6): закрите таємне не віддає
    /// ні назви, ні умови, ні прогресу, а пасхалки до знахідки немає зовсім — інакше вона поїхала б у
    /// VoiceOver, e2e-дерево й лічильник.
    public func snapshots(gates: AchievementGates = .allOpen) -> [AchievementSnapshot] {
        let progressByKey = Dictionary(
            store.allAchievementProgress().map { ($0.defKey, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let firstEgg = AchievementCatalog.all
            .filter { $0.secrecy.isEgg }
            .compactMap { definition in progressByKey[definition.key]?.unlockedAt.map { (definition.key, $0) } }
            .min { $0.1 < $1.1 }?.0

        return AchievementCatalog.all.compactMap { definition in
            let progress = progressByKey[definition.key]
            let isUnlocked = progress?.isUnlocked ?? false
            if definition.secrecy.isEgg && !isUnlocked { return nil }

            let hint = isUnlocked ? nil : definition.hint
            let lockedCaption = isUnlocked || gates.isOpen(definition.gate) ? nil : definition.gate?.caption
            // Прогрес таємного не показуємо ніде, а залежного від вимкненої функції — замінює підпис.
            let showsProgress = hint == nil && lockedCaption == nil

            return AchievementSnapshot(
                key: definition.key,
                title: hint == nil ? definition.title : AchievementSnapshot.maskedTitle,
                details: hint.map { "«\($0)»" } ?? definition.details,
                emoji: hint == nil ? definition.emoji : AchievementSnapshot.maskedEmoji,
                category: definition.category,
                value: showsProgress ? progress?.value ?? 0 : 0,
                target: definition.target,
                isUnlocked: isUnlocked,
                isSecret: definition.isSecret,
                rewardXp: definition.rewardXp,
                unlockedAt: progress?.unlockedAt,
                isNew: progress.map { $0.isUnlocked && $0.seenAt == nil } ?? false,
                isMasked: hint != nil,
                isEgg: definition.secrecy.isEgg,
                lockedCaption: lockedCaption,
                note: definition.key == firstEgg ? AchievementCatalog.firstEggNote : nil
            )
        }
    }

    public func markAllSeen(at date: Date) {
        for progress in store.allAchievementProgress() where progress.isUnlocked && progress.seenAt == nil {
            progress.seenAt = date
        }
        store.save()
    }

    /// Переглянуто одну картку — гасимо крапку лише на ній, решта нових лишаються новими.
    public func markSeen(key: String, at date: Date) {
        guard let progress = store.achievementProgress(defKey: key),
              progress.isUnlocked, progress.seenAt == nil else { return }
        progress.seenAt = date
        store.save()
    }

    public var hasUnseenUnlocks: Bool {
        store.allAchievementProgress().contains { $0.isUnlocked && $0.seenAt == nil }
    }

    static func ref(_ key: String) -> UUID {
        DeterministicID.uuid(from: "achievement:\(key)")
    }

    // MARK: - Внутрішнє

    private func progress(for definition: AchievementDefinition) -> AchievementProgress {
        if let existing = store.achievementProgress(defKey: definition.key) { return existing }
        let created = AchievementProgress(defKey: definition.key, target: definition.target)
        store.insertAchievement(created)
        return created
    }

    /// Скільки відкрито: усього (колекції теж досягнення) і з основного каталогу без «Усе зібрано».
    private func collectionCounts() -> (all: Int, core: Int) {
        var counts = (all: 0, core: 0)
        for definition in AchievementCatalog.all {
            guard store.achievementProgress(defKey: definition.key)?.isUnlocked == true else { continue }
            counts.all += 1
            if Self.countsTowardCore(definition) { counts.core += 1 }
        }
        return counts
    }

    /// «Усе зібрано» рахує решту основного каталогу — без себе.
    private static func countsTowardCore(_ definition: AchievementDefinition) -> Bool {
        guard definition.isCore else { return false }
        if case .collection(.core) = definition.rule { return false }
        return true
    }

    private func value(of rule: AchievementRule, _ inputs: AchievementInputs, counts: (all: Int, core: Int)) -> Double {
        switch rule {
        case .metric(let metricRule): return metricRule.value(in: inputs.rules)
        case let .burst(key, count, seconds): return inputs.burst(key, count, seconds)
        // Перший рівень — стартовий, не прогрес: інакше «Струмок» стояв би «в процесі» на чистій установці.
        case .level: return inputs.level > 1 ? Double(inputs.level) : 0
        case .history(let fact): return inputs.history.value(of: fact)
        case .game(let fact): return inputs.game[fact] ?? 0
        case .collection(.all): return Double(counts.all)
        case .collection(.core): return Double(counts.core)
        }
    }
}
