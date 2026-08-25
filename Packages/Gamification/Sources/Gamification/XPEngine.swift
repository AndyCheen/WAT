import Foundation
import Core
import Persistence
import Metrics

/// Нарахування й відкат досвіду. Рівень — завжди похідна від журналу `XPEntry`.
@MainActor
public final class XPEngine {
    private let store: GamificationStoreProtocol
    private let metrics: MetricsService
    private let calendar: CalendarService
    public let curve: LevelCurve
    public var rules: XPRules

    public init(
        store: GamificationStoreProtocol,
        metrics: MetricsService,
        calendar: CalendarService,
        curve: LevelCurve = LinearLevelCurve(),
        rules: XPRules = .default
    ) {
        self.store = store
        self.metrics = metrics
        self.calendar = calendar
        self.curve = curve
        self.rules = rules
    }

    /// Читається з кешу `LevelState`: перечитувати весь журнал на кожен рендер
    /// і на кожне нарахування — квадратична складність (див. PerformanceTests).
    public func progress() -> LevelProgress {
        LevelCalculator.progress(totalXp: store.levelState().totalXp, curve: curve)
    }

    /// Перерахунок кешу з журналу — на старті застосунку та після міграцій.
    @discardableResult
    public func recalculateFromJournal(at date: Date) -> LevelProgress {
        let result = LevelCalculator.progress(totalXp: store.totalXP(), curve: curve)
        syncCache(result, at: date)
        return result
    }

    @discardableResult
    public func award(
        amount: Int,
        reason: XPReason,
        refId: UUID?,
        at date: Date,
        streak: Int = 0
    ) -> Int {
        guard amount > 0 else { return 0 }
        let levelBefore = progress().level
        let multiplier = reason == .intake ? rules.multiplier(streak: streak) : 1

        let entry = XPEntry(
            amount: amount,
            multiplier: multiplier,
            reason: reason,
            refId: refId,
            dayKey: calendar.dayKey(for: date).rawValue,
            createdAt: date
        )
        store.insertXP(entry)

        let gained = entry.effectiveAmount
        let after = LevelCalculator.progress(totalXp: store.levelState().totalXp + gained, curve: curve)
        syncCache(after, at: date)
        metrics.record(MetricEvent(name: .xpEarned, value: Double(gained), occurredAt: date, sourceRef: entry.id))
        if after.level > levelBefore {
            metrics.record(MetricEvent(
                name: .levelReached, value: Double(after.level), occurredAt: date,
                sourceRef: DeterministicID.uuid(from: "level:\(after.level)")
            ))
        }
        return gained
    }

    /// Відкат усіх нарахувань, повʼязаних з дією.
    @discardableResult
    public func revert(refId: UUID, at date: Date) -> Int {
        let entries = store.xpEntries(refId: refId).filter { $0.revertedAt == nil }
        guard !entries.isEmpty else { return 0 }
        var removed = 0
        for entry in entries {
            removed += entry.effectiveAmount
            entry.revertedAt = date
            metrics.revert(sourceRef: entry.id, at: date)
        }
        let after = LevelCalculator.progress(
            totalXp: max(0, store.levelState().totalXp - removed), curve: curve
        )
        syncCache(after, at: date)
        return removed
    }

    private func syncCache(_ progress: LevelProgress, at date: Date) {
        let state = store.levelState()
        state.level = progress.level
        state.totalXp = progress.totalXp
        state.xpIntoLevel = progress.xpIntoLevel
        state.xpForNextLevel = progress.xpForNextLevel
        state.updatedAt = date
        store.save()
    }
}
