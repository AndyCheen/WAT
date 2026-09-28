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

    /// Заморозки, які `recompute` повернув в інвентар, бо заморожений день усе ж закрили.
    /// Черга, а не повернене значення: метрику `prize.activated` відкочує координатор —
    /// рушій серій про шину метрик не знає.
    private var returnedFreezes: [UUID] = []

    public init(
        store: GamificationStoreProtocol,
        dayLogs: DayLogRepositoryProtocol,
        calendar: CalendarService
    ) {
        self.store = store
        self.dayLogs = dayLogs
        self.calendar = calendar
    }

    /// Кількість готових заморозок тут свідомо не рахується: `summary()` читається кілька
    /// разів на кожну порцію, а заморозки — це інвентар (`GamificationService.streakSummary()`).
    public func summary() -> StreakSummary {
        let state = store.streakState()
        return StreakSummary(
            current: state.currentStreak,
            longest: state.longestStreak,
            freezeTokens: 0,
            lastCountedDay: state.lastCountedDayKey.map { DayKey(rawValue: $0) }
        )
    }

    /// Ланцюг серії тримають дні зі 100 % норми (ТЗ §5.3) і заморожені, але **рахуються
    /// лише перші**: серія міряє дні, коли людина пила норму, а не витрачені предмети
    /// (SPEC-PRIZES §6.3). Серія 12 → пропуск → заморозка → серія лишається 12.
    ///
    /// Заморожений день, який потім виявився виконаним, розморожується, а його приз
    /// повертається в `.ready` — тому заморожувати «сьогодні» можна без ризику.
    @discardableResult
    public func recompute(at date: Date) -> StreakSummary {
        let state = store.streakState()
        let completed = Set(dayLogs.allDayLogs().filter { $0.goalMet }.map(\.dayKey))
        returnFreezes(on: Set(state.frozenDayKeys).intersection(completed), state: state)
        let frozen = Set(state.frozenDayKeys)
        let counted = completed.union(frozen)

        let today = calendar.dayKey(for: date)
        var cursor = counted.contains(today.rawValue) ? today : calendar.dayKey(offsetDays: -1, from: today)
        var current = 0
        var lastCounted: String?

        while counted.contains(cursor.rawValue) {
            if completed.contains(cursor.rawValue) { current += 1 }
            if lastCounted == nil { lastCounted = cursor.rawValue }
            cursor = calendar.dayKey(offsetDays: -1, from: cursor)
        }

        state.currentStreak = current
        state.lastCountedDayKey = lastCounted
        state.longestStreak = Self.longestRun(in: counted, completed: completed, calendar: calendar)
        state.updatedAt = date
        store.save()

        return summary()
    }

    /// Який день заморозить заморозка, використана зараз.
    ///
    /// **Рішення від 24.09.2026 (SPEC-PRIZES §6.2).** «Зараховано» — день із виконаною
    /// нормою або заморожений.
    ///
    /// 1. Учора зараховано → сьогодні.
    /// 2. Учора не зараховано, а на позавчора закінчується серія ≥ 1 дня → учора.
    /// 3. Учора не зараховано і позавчора серії не було → сьогодні.
    /// 4. Доповнення: ціль за п. 1–3 — сьогодні, але сьогодні вже зараховано →
    ///    `.todayAlreadyCounted`, кнопка неактивна: заморозка згоріла б без жодного ефекту.
    ///
    /// Читає `DayLog` лише за три дні, а не всю історію — картку відкривають часто.
    /// Повна історія потрібна тільки для числа серії, яку рятує «вчора».
    public func freezeTarget(at date: Date) -> FreezeTarget {
        let state = store.streakState()
        let frozen = Set(state.frozenDayKeys)
        let today = calendar.dayKey(for: date)
        let yesterday = calendar.dayKey(offsetDays: -1, from: today)
        let dayBefore = calendar.dayKey(offsetDays: -2, from: today)

        func isCounted(_ day: DayKey) -> Bool {
            frozen.contains(day.rawValue) || dayLogs.existingDayLog(for: day)?.goalMet == true
        }

        if !isCounted(yesterday), isCounted(dayBefore) {
            return .yesterday(savedStreak: streakLength(endingAt: dayBefore, frozen: frozen))
        }
        return isCounted(today) ? .todayAlreadyCounted : .today
    }

    /// Заморожує день. Жетонів більше немає — предмет і є жетон, його стан міняє
    /// координатор (`GamificationService.useFreeze(prizeId:)`).
    @discardableResult
    func freeze(day: DayKey, at date: Date) -> Bool {
        let state = store.streakState()
        guard !state.frozenDayKeys.contains(day.rawValue) else { return false }
        state.frozenDayKeys.append(day.rawValue)
        state.lastFreezeUsedDayKey = day.rawValue
        store.save()
        recompute(at: date)
        return true
    }

    /// Забирає заморозки, повернуті з останнього виклику, і очищає чергу.
    func takeReturnedFreezes() -> [UUID] {
        defer { returnedFreezes.removeAll() }
        return returnedFreezes
    }

    // MARK: - Внутрішнє

    private func returnFreezes(on days: Set<String>, state: StreakState) {
        guard !days.isEmpty else { return }
        state.frozenDayKeys.removeAll { days.contains($0) }
        for item in store.rewardItems(defKey: RewardCatalog.freezeKey)
        where item.state == .used && days.contains(item.usedOnDayKey ?? "") {
            item.state = .ready
            item.usedOnDayKey = nil
            item.activatedAt = nil
            returnedFreezes.append(item.id)
        }
    }

    /// Скільки днів із нормою в ланцюгу, що закінчується на `day`.
    private func streakLength(endingAt day: DayKey, frozen: Set<String>) -> Int {
        let completed = Set(dayLogs.allDayLogs().filter { $0.goalMet }.map(\.dayKey))
        var cursor = day
        var length = 0
        while completed.contains(cursor.rawValue) || frozen.contains(cursor.rawValue) {
            if completed.contains(cursor.rawValue) { length += 1 }
            cursor = calendar.dayKey(offsetDays: -1, from: cursor)
        }
        return length
    }

    /// Найдовша серія за всю історію — перераховується з тих самих даних.
    /// Ланцюг тримають усі зараховані дні, а довжину дають лише виконані.
    static func longestRun(in counted: Set<String>, completed: Set<String>, calendar: CalendarService) -> Int {
        guard !counted.isEmpty else { return 0 }
        let sorted = counted.map { DayKey(rawValue: $0) }.sorted()
        func weight(_ day: DayKey) -> Int { completed.contains(day.rawValue) ? 1 : 0 }
        var best = weight(sorted[0])
        var run = best
        for index in 1..<sorted.count {
            if calendar.daysBetween(sorted[index - 1], sorted[index]) == 1 {
                run += weight(sorted[index])
            } else {
                run = weight(sorted[index])
            }
            best = max(best, run)
        }
        return best
    }
}
