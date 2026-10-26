import Foundation
import Core
import Persistence

/// День завдань (SPEC-QUESTS §3–5): факти одного дня без SwiftData — одна оцінка для щоденних, тижневих і
/// несподіваних. Розклад і норма — зі знімка дня (`UserProfile.schedule(for:isWeekend:)`, `goalMlSnapshot`), як у
/// цілей частин доби: зміна підйому пізніше не переписує вже оціненого.
public struct QuestDay: Sendable, Equatable {
    public let day: DayKey
    public let goalMl: Int
    public let schedule: DaySchedule
    /// Активні порції за часом.
    public let portions: [TimedPortion]
    /// З `DayLog`, а не сума `portions`: тести й демо пишуть підсумок дня без порцій.
    public let totalMl: Int
    public let goalMet: Bool
    /// Норму закрито раніше за будь-яке нагадування (`day.goalAhead`, Д4).
    public let goalAhead: Bool
    public let curve: PaceCurve
    public let blocks: [GoalBlock]

    public init(day: DayKey, goalMl: Int, schedule: DaySchedule, portions: [TimedPortion],
                totalMl: Int? = nil, goalAhead: Bool = false) {
        let total = totalMl ?? portions.reduce(0) { $0 + $1.ml }
        self.day = day
        self.goalMl = goalMl
        self.schedule = schedule
        self.portions = portions.sorted { $0.minute < $1.minute }
        self.totalMl = total
        self.goalMet = goalMl > 0 && total >= goalMl
        self.goalAhead = goalAhead
        curve = schedule.curve(goalMl: goalMl)
        blocks = curve.goalBlocks()
    }

    /// День із запису: порції — лише не видалені, хвилина — у поясі календаря.
    init(log: DayLog, schedule: DaySchedule, goalAhead: Bool, calendar: CalendarService) {
        let portions = (log.intakes ?? []).filter { !$0.isDeleted }.map {
            TimedPortion(minute: calendar.minuteOfDay($0.createdAt), ml: $0.amountMl)
        }
        self.init(day: DayKey(rawValue: log.dayKey), goalMl: log.goalMlSnapshot, schedule: schedule,
                  portions: portions, totalMl: log.totalMl, goalAhead: goalAhead)
    }

    public var isActive: Bool { totalMl > 0 || !portions.isEmpty }
    public var firstMinute: Int? { portions.first?.minute }

    /// Хвилина, коли норму закрила порція. `nil` — не закрито або підсумок без порцій.
    public var goalMinute: Int? {
        var running = 0
        for portion in portions {
            running += portion.ml
            if running >= goalMl { return portion.minute }
        }
        return nil
    }

    /// Хвилина порції, що добрала `percent` % норми; `nil` — за день не добрано (база адаптивних цілей, WAT-67).
    public func minute(reaching percent: Int) -> Int? {
        let needed = (goalMl * percent + 99) / 100
        var running = 0
        for portion in portions {
            running += portion.ml
            if running >= needed { return portion.minute }
        }
        return nil
    }

    /// Випито до T — строго раніше (ТЗ §7), як у блоків цілей. Порції до підйому теж тут.
    public func drunk(before minute: Int) -> Int {
        portions.reduce(0) { $1.minute < minute ? $0 + $1.ml : $0 }
    }

    /// Блок за індексом — останній, якщо в цей день блоків менше (короткий розклад).
    public func block(_ index: Int?) -> GoalBlock? {
        guard let index, !blocks.isEmpty else { return nil }
        return blocks[min(max(0, index), blocks.count - 1)]
    }
}
