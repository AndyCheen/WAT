import Foundation
import Core
import Persistence
import Metrics

/// Серії днів. Стан завжди перераховується з денних логів, тому будь-який відкат
/// автоматично дає коректну серію — окремої «зворотної» логіки не потрібно.
@MainActor
public final class StreakEngine {
    private let store: GamificationStoreProtocol
    private let dayLogs: DayLogRepositoryProtocol
    private let calendar: CalendarService

    public init(
        store: GamificationStoreProtocol,
        dayLogs: DayLogRepositoryProtocol,
        calendar: CalendarService
    ) {
        self.store = store
        self.dayLogs = dayLogs
        self.calendar = calendar
    }

    public func summary() -> StreakSummary {
        let state = store.streakState()
        return StreakSummary(
            current: state.currentStreak,
            longest: state.longestStreak,
            freezeTokens: state.freezeTokens,
            lastCountedDay: state.lastCountedDayKey.map { DayKey(rawValue: $0) }
        )
    }

    /// День зараховується в серію при 100 % норми (ТЗ §5.3) або якщо був заморожений.
    @discardableResult
    public func recompute(at date: Date) -> StreakSummary {
        let state = store.streakState()
        let frozen = Set(state.frozenDayKeys)
        let completed = Set(
            dayLogs.allDayLogs().filter { $0.goalMet }.map(\.dayKey)
        )
        let counted = completed.union(frozen)

        let today = calendar.dayKey(for: date)
        var cursor = counted.contains(today.rawValue) ? today : calendar.dayKey(offsetDays: -1, from: today)
        var current = 0
        var lastCounted: String?

        while counted.contains(cursor.rawValue) {
            current += 1
            if lastCounted == nil { lastCounted = cursor.rawValue }
            cursor = calendar.dayKey(offsetDays: -1, from: cursor)
        }

        state.currentStreak = current
        state.lastCountedDayKey = lastCounted
        state.longestStreak = Self.longestRun(in: counted, calendar: calendar)
        state.updatedAt = date
        store.save()

        return summary()
    }

    /// Витрачає «заморозку серії», щоб пропущений день не обірвав серію (ТЗ §5.3).
    @discardableResult
    public func useFreeze(on day: DayKey, at date: Date) -> Bool {
        let state = store.streakState()
        guard state.freezeTokens > 0, !state.frozenDayKeys.contains(day.rawValue) else { return false }
        state.freezeTokens -= 1
        state.frozenDayKeys.append(day.rawValue)
        state.lastFreezeUsedDayKey = day.rawValue
        store.save()
        recompute(at: date)
        return true
    }

    public func grantFreezeToken(count: Int = 1) {
        let state = store.streakState()
        state.freezeTokens += count
        store.save()
    }

    /// Найдовша серія за всю історію — перераховується з тих самих даних.
    static func longestRun(in counted: Set<String>, calendar: CalendarService) -> Int {
        guard !counted.isEmpty else { return 0 }
        let sorted = counted.map { DayKey(rawValue: $0) }.sorted()
        var best = 1
        var run = 1
        for index in 1..<sorted.count {
            if calendar.daysBetween(sorted[index - 1], sorted[index]) == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }
}
