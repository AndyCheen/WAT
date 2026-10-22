import Foundation
import Core
import Metrics

/// Як рахується дедлайн T умови «до T» (SPEC-QUESTS §3, §4.4).
public enum DeadlineRule: Sendable, Equatable {
    /// W + m, униз до 30 хв (Д1).
    case wakePlus(minutes: Int)
    /// Хвилина, коли крива темпу дня досягає частки норми, униз до 30 хв (Д2, Д10, Д11).
    case curveShare(Double)
    /// Особистий дедлайн норми (§4.4).
    case personalGoal
    /// Кінець блоку цілі (Д7).
    case blockEnd
}

/// Умова одного дня — спільна для щоденних, тижневих («день зараховано, якщо…») і несподіваних.
public enum DayCondition: Sendable, Equatable {
    /// ≥ частки норми до T (Д1, Д2, Д11, Д3; Т6, Т8). Частка 1 — сама норма, без округлення.
    case shareBy(Double, DeadlineRule)
    /// ≥ min(P, 250 мл) до W + m (Д5, Т5). Порції до підйому теж рахуються.
    case wakeGlass(withinMinutes: Int)
    /// N порцій від `minMl` (Д6), за потреби — до T (Д10). N — з інстансу.
    case glasses(minMl: Int, deadline: DeadlineRule?)
    /// Ціль блоку досягнуто (Д7). Блок — з інстансу.
    case blockReached
    /// У кожному блоці є порція від `minMl` (Д8).
    case portionInEachBlock(minMl: Int)
    /// Закрито всі блоки (Д9, Т7).
    case allBlocks
    /// Норму закрито раніше за будь-яке нагадування (Д4).
    case goalAhead
    case goal
    case halfGoal
    case anyPortion
}

/// Умова завдання цілком: день, дні тижня з умовою, або архівне правило шини.
public enum QuestCondition: Sendable, Equatable {
    case day(DayCondition)
    /// N днів з умовою від дня видачі до неділі (Т1, Т3, Т5–Т8).
    case daysCount(DayCondition)
    /// Найдовший ланцюжок днів з умовою ≥ N (Т2).
    case daysRun(DayCondition)
    /// Субота й неділя з умовою (Т4).
    case weekend(DayCondition)
    /// Архівні ключі до WAT-63 (ТЗ §3.7): лічильник шини проти цілі.
    case legacy(MetricRule, QuestTarget)
}

/// Що треба для оцінки, крім самого дня.
public struct QuestParams: Sendable, Equatable {
    /// T, зафіксоване у мить видачі (щоденні). `nil` — рахувати з розкладу дня (тижневі).
    public var deadlineMinute: Int?
    /// Медіана закриття норми — опора особистого дедлайну дня, коли T не зафіксоване (Т8).
    public var goalMedianMinute: Int?
    public var blockIndex: Int?
    public var count: Int?
    /// «Моя склянка» P.
    public var glassMl: Int
    public var unit: VolumeUnit

    public init(deadlineMinute: Int? = nil, goalMedianMinute: Int? = nil, blockIndex: Int? = nil, count: Int? = nil,
                glassMl: Int = 250, unit: VolumeUnit = .milliliters) {
        self.deadlineMinute = deadlineMinute
        self.goalMedianMinute = goalMedianMinute
        self.blockIndex = blockIndex
        self.count = count
        self.glassMl = glassMl
        self.unit = unit
    }
}

public struct QuestProgress: Sendable, Equatable {
    public let progress: Double
    public let target: Double
    public let met: Bool

    public init(progress: Double, target: Double, met: Bool) {
        self.progress = progress
        self.target = target
        self.met = met
    }

    static func volume(_ drunk: Int, _ target: Int) -> QuestProgress {
        QuestProgress(progress: Double(drunk), target: Double(target), met: drunk >= target)
    }

    static func count(_ done: Int, _ target: Int) -> QuestProgress {
        QuestProgress(progress: Double(done), target: Double(target), met: done >= target && target > 0)
    }
}

/// Числа умов, спільні для пікерів і оцінки.
public enum QuestRules {
    /// Д5: «склянка» — не більше за звичайну порцію, навіть якщо P більша.
    public static let wakeGlassCapMl = 250
    /// Кількісні умови рахують лише порції від 150 мл (ТЗ §0, п. 4): XP навмисно не платить за дрібнення.
    public static let glassMinMl = 150
    /// Час T у назвах і умовах — униз до 30 хв (§4.4).
    public static let deadlineStepMinutes = 30
    /// Особистий дедлайн: медіана закриття мінус 30 хв, у межах [Z − 4 год, Z − 2 год]; без 5 днів із нормою —
    /// Z − 3 год (§4.4).
    public static let personalGoalLeadMinutes = 30
    public static let personalGoalWindow = (earliest: 240, latest: 120)
    public static let personalGoalFallback = 180
    public static let personalGoalMinDays = 5

    /// Об'єм так, як людина його бачить, у мілілітрах: метрична — до 50 мл, унції — до цілої унції (§4.4).
    /// Порівнювати треба з мілілітрами показаного числа: «8 унц.» — це 237 мл, а не 250 (WAT-59).
    public static func shownMl(_ ml: Double, unit: VolumeUnit) -> Int {
        unit.isMetric
            ? Int((ml / 50).rounded()) * 50
            : unit.milliliters(units: Int((ml / unit.mlPerUnit).rounded()))
    }

    static func floorToStep(_ minute: Int) -> Int { minute / deadlineStepMinutes * deadlineStepMinutes }

    /// §4.4: від медіани хвилини закриття норми; `nil` — менше 5 днів із нормою.
    public static func personalGoalMinute(median: Int?, sleepMinutes: Int) -> Int {
        guard let median else { return floorToStep(sleepMinutes - personalGoalFallback) }
        let clamped = min(max(median - personalGoalLeadMinutes, sleepMinutes - personalGoalWindow.earliest),
                          sleepMinutes - personalGoalWindow.latest)
        return floorToStep(clamped)
    }
}

extension DeadlineRule {
    func minute(on day: QuestDay, params: QuestParams) -> Int? {
        switch self {
        case .wakePlus(let minutes):
            return QuestRules.floorToStep(day.schedule.wakeMinutes + minutes)
        case .curveShare(let share):
            return day.curve.minute(reaching: Double(day.goalMl) * share).map { QuestRules.floorToStep(Int($0)) }
        case .personalGoal:
            return QuestRules.personalGoalMinute(median: params.goalMedianMinute, sleepMinutes: day.schedule.sleepMinutes)
        case .blockEnd:
            return day.block(params.blockIndex)?.toMinute
        }
    }
}

extension DayCondition {
    /// Дедлайн умови цього дня: зафіксований на інстансі або з розкладу дня. `nil` — до кінця дня.
    public func deadline(on day: QuestDay, params: QuestParams) -> Int? {
        if let fixed = params.deadlineMinute, hasDeadline { return fixed }
        switch self {
        case .shareBy(_, let rule): return rule.minute(on: day, params: params)
        case .wakeGlass(let within): return day.schedule.wakeMinutes + within
        case .glasses(_, let rule): return rule?.minute(on: day, params: params)
        case .blockReached: return DeadlineRule.blockEnd.minute(on: day, params: params)
        case .portionInEachBlock, .allBlocks, .goalAhead, .goal, .halfGoal, .anyPortion: return nil
        }
    }

    var hasDeadline: Bool {
        switch self {
        case .shareBy, .wakeGlass, .blockReached: return true
        case .glasses(_, let rule): return rule != nil
        case .portionInEachBlock, .allBlocks, .goalAhead, .goal, .halfGoal, .anyPortion: return false
        }
    }

    /// Прогрес у мл чи штуках — чиста функція дня й параметрів.
    public func evaluate(on day: QuestDay, params: QuestParams) -> QuestProgress {
        let deadline = deadline(on: day, params: params) ?? 24 * 60
        switch self {
        case .shareBy(let share, _):
            let target = share >= 1 ? day.goalMl : QuestRules.shownMl(Double(day.goalMl) * share, unit: params.unit)
            return .volume(day.drunk(before: deadline), target)
        case .wakeGlass:
            let target = QuestRules.shownMl(Double(min(params.glassMl, QuestRules.wakeGlassCapMl)), unit: params.unit)
            return .volume(day.drunk(before: deadline), target)
        case .glasses(let minMl, _):
            let threshold = QuestRules.shownMl(Double(minMl), unit: params.unit)
            let done = day.portions.filter { $0.ml >= threshold && $0.minute < deadline }.count
            return .count(done, params.count ?? 1)
        case .blockReached:
            guard let block = day.block(params.blockIndex) else { return .count(0, 1) }
            return .volume(block.drunkMl(of: day.portions), block.targetMl)
        case .portionInEachBlock(let minMl):
            let threshold = QuestRules.shownMl(Double(minMl), unit: params.unit)
            let done = day.blocks.filter { block in
                day.portions.contains { $0.ml >= threshold && block.contains(minute: $0.minute) }
            }.count
            return .count(done, day.blocks.count)
        case .allBlocks:
            let done = day.portions.isEmpty ? 0 : day.blocks.filter { $0.isReached(by: day.portions) }.count
            return .count(done, day.blocks.count)
        case .goalAhead:
            // Норму закрито з нагадуванням — день для Д4 вже не врятувати, але кільце показує випите чесно.
            return QuestProgress(progress: Double(min(day.totalMl, day.goalMl)), target: Double(day.goalMl),
                                 met: day.goalMet && day.goalAhead)
        case .goal:
            return QuestProgress(progress: Double(day.totalMl), target: Double(day.goalMl), met: day.goalMet)
        case .halfGoal:
            return .volume(day.totalMl, QuestRules.shownMl(Double(day.goalMl) / 2, unit: params.unit))
        case .anyPortion:
            return .count(day.isActive ? 1 : 0, 1)
        }
    }

    /// Чи рахується прогрес у мілілітрах — для підпису «ще N мл».
    var measuresVolume: Bool {
        switch self {
        case .shareBy, .wakeGlass, .blockReached, .goalAhead, .goal, .halfGoal: return true
        case .glasses, .portionInEachBlock, .allBlocks, .anyPortion: return false
        }
    }
}

extension QuestCondition {
    /// Умова одного дня всередині, якщо вона є (у тижневих — «день зараховано, якщо…»).
    public var dayCondition: DayCondition? {
        switch self {
        case .day(let condition), .daysCount(let condition), .daysRun(let condition), .weekend(let condition):
            return condition
        case .legacy:
            return nil
        }
    }

    /// Оцінка за днями від дня видачі до `today` включно. `days` — дні періоду за зростанням, без майбутніх.
    func evaluate(days: [QuestDay], params: QuestParams) -> QuestProgress {
        switch self {
        case .day(let condition):
            guard let day = days.last else { return .count(0, 1) }
            return condition.evaluate(on: day, params: params)
        case .daysCount(let condition):
            return .count(days.filter { condition.evaluate(on: $0, params: params).met }.count, params.count ?? 1)
        case .daysRun(let condition):
            var best = 0, run = 0, previous: Int?
            for day in days {
                let ordinal = day.day.ordinal
                if condition.evaluate(on: day, params: params).met {
                    run = previous == ordinal - 1 ? run + 1 : 1
                    previous = ordinal
                    best = max(best, run)
                } else {
                    run = 0
                    previous = nil
                }
            }
            return .count(best, params.count ?? 1)
        case .weekend(let condition):
            let done = days.filter { $0.day.weekdayIndex >= 5 && condition.evaluate(on: $0, params: params).met }.count
            return .count(done, 2)
        case .legacy:
            return .count(0, 1)
        }
    }
}
