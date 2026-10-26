import Foundation
import Core

/// Історія днів до вчора включно — підсумки, з яких складаються входи пікерів (§4.1, §5). Чиста: дні приходять
/// готовими `QuestDay`, тож пороги перевіряються тестами без бази.
public struct QuestHistory: Sendable {
    public let today: DayKey
    /// Перший день із порцією; дні до нього не рахуються ні в частки, ні в повні тижні.
    public let firstActive: DayKey?
    /// Дні з записом, за ordinal. Дня без запису немає — він неактивний і без норми.
    private let days: [Int: QuestDay]

    public init(today: DayKey, firstActive: DayKey?, days: [QuestDay]) {
        self.today = today
        self.firstActive = firstActive
        self.days = Dictionary(days.filter { $0.day < today }.map { ($0.day.ordinal, $0) },
                               uniquingKeysWith: { _, last in last })
    }

    /// Пороги слабких місць (§4.5).
    static let lateFirstGlassMinutes = 90
    static let lateGoalMinutes = 120
    static let lateGoalMinDays7 = 4

    /// Останні `count` днів до вчора включно, від найдавнішого; без запису — `nil`.
    func window(_ count: Int) -> [QuestDay?] {
        let end = today.ordinal - 1
        return ((end - count + 1)...end).map { days[$0] }
    }

    public var goalMetYesterday: Bool { days[today.ordinal - 1]?.goalMet ?? false }

    public func goalDays(_ count: Int) -> Int { window(count).filter { $0?.goalMet ?? false }.count }

    /// Медіана хвилини закриття норми за 14 днів — лише з 5 днів із нормою (§4.4).
    public var goalMedianMinute: Int? {
        let minutes = window(14).compactMap { $0?.goalMinute }
        guard minutes.count >= QuestRules.personalGoalMinDays else { return nil }
        return WeeklyQuestPicker.median(minutes)
    }

    public func weakSpots(today schedule: DaySchedule) -> QuestWeakSpots {
        let recent = window(14).compactMap { $0 }
        let firstOffsets = recent.compactMap { day in day.firstMinute.map { $0 - day.schedule.wakeMinutes } }
        let goalGaps = recent.compactMap { day in day.goalMinute.map { day.schedule.sleepMinutes - $0 } }
        return QuestWeakSpots(
            lateFirstGlass: (WeeklyQuestPicker.median(firstOffsets) ?? 0) > Self.lateFirstGlassMinutes,
            lateGoal: goalDays(7) < Self.lateGoalMinDays7
                || (WeeklyQuestPicker.median(goalGaps).map { $0 < Self.lateGoalMinutes } ?? false)
        )
    }

    /// Найслабший блок за 14 днів: найменша медіана «випито в блоці / ціль». Дні з іншим числом блоків
    /// (інший розклад) не порівнюються. Нічия — за `StableHash`, без історії — усі рівні.
    public func weakBlock(blockCount: Int, seed: String) -> WeakBlock? {
        guard blockCount > 0 else { return nil }
        let recent = window(14).compactMap { $0 }.filter { $0.isActive && $0.blocks.count == blockCount }
        let medians: [Double?] = (0..<blockCount).map { index in
            let ratios = recent.map { day -> Double in
                let block = day.blocks[index]
                return block.targetMl > 0 ? Double(block.drunkMl(of: day.portions)) / Double(block.targetMl) : 1
            }
            guard !ratios.isEmpty else { return nil }
            let sorted = ratios.sorted()
            return sorted.count.isMultiple(of: 2)
                ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : sorted[sorted.count / 2]
        }
        let lowest = medians.compactMap { $0 }.min()
        let weakest = (0..<blockCount).filter { medians[$0] == lowest }
        let index = weakest[Int(StableHash.fnv1a("\(seed)|\(today.rawValue)|block") % UInt64(weakest.count))]
        return WeakBlock(index: index, median: medians[index])
    }

    /// База адаптивних цілей (WAT-67): коли людина зазвичай досягає 25 / 50 / 75 / 100 % норми (14 днів), скільки
    /// склянок п'є за день і до половини кривої (7 днів), як часто закриває блоки й норму раніше за нагадування.
    public func baseline(glassMinMl: Int = QuestRules.glassMinMl) -> QuestBaseline {
        let recent = window(14).compactMap { $0 }.filter(\.isActive)
        var shares: [Int: Int] = [:]
        for percent in [25, 50, 75, 100] {
            let minutes = recent.compactMap { $0.minute(reaching: percent) }
            if minutes.count >= QuestBaseline.minDays { shares[percent] = WeeklyQuestPicker.median(minutes) }
        }
        let week = window(7).compactMap { $0 }.filter(\.isActive)
        let glasses = week.map { day in day.portions.filter { $0.ml >= glassMinMl }.count }
        let beforeHalf = week.compactMap { day -> Int? in
            guard let half = day.curve.minute(reaching: Double(day.goalMl) * 0.5) else { return nil }
            let deadline = QuestRules.floorToStep(Int(half))
            return day.portions.filter { $0.ml >= glassMinMl && $0.minute < deadline }.count
        }
        let median = { (values: [Int]) in values.count >= QuestBaseline.minDays ? WeeklyQuestPicker.median(values) : nil }
        let portions = week.flatMap { $0.portions.map(\.ml) }
        return QuestBaseline(
            shareMinutes: shares, glasses: median(glasses), glassesBeforeHalf: median(beforeHalf),
            portionMl: portions.count >= QuestBaseline.minDays ? WeeklyQuestPicker.median(portions) : nil,
            allBlocksDays14: recent.filter { day in day.blocks.allSatisfy { $0.isReached(by: day.portions) } }.count,
            everyBlockDays14: recent.filter { day in
                DayCondition.portionInEachBlock(minMl: glassMinMl).evaluate(on: day, params: QuestParams()).met
            }.count,
            goalAheadDays7: window(7).compactMap { $0 }.filter(\.goalAhead).count
        )
    }

    /// Днів за 7 з умовою — база тижневих «Звичок» (WAT-67).
    public func days7(_ condition: DayCondition, params: QuestParams) -> Int {
        window(7).compactMap { $0 }.filter { condition.evaluate(on: $0, params: params).met }.count
    }

    /// Днів за 7, коли вдавалось Д2 — половина норми до T½ свого дня.
    public var halfByDays7: Int {
        let condition = DayCondition.shareBy(0.5, .curveShare(0.5))
        return window(7).compactMap { $0 }.filter { condition.evaluate(on: $0, params: QuestParams()).met }.count
    }

    /// Частка днів із нормою за 4 тижні — у вихідні й у будні; лише від першого дня людини.
    public var goalShares: (weekend: Double?, weekday: Double?) {
        let start = firstActive?.ordinal ?? today.ordinal
        var weekend = (goal: 0, all: 0), weekday = (goal: 0, all: 0)
        for ordinal in (today.ordinal - 28)..<today.ordinal where ordinal >= start {
            let met = days[ordinal]?.goalMet ?? false
            if DayKey.weekdayIndex(ordinal: ordinal) >= 5 {
                weekend.all += 1
                if met { weekend.goal += 1 }
            } else {
                weekday.all += 1
                if met { weekday.goal += 1 }
            }
        }
        func share(_ value: (goal: Int, all: Int)) -> Double? { value.all > 0 ? Double(value.goal) / Double(value.all) : nil }
        return (share(weekend), share(weekday))
    }

    /// Днів із нормою в кожному з (до) 4 повних тижнів перед поточним — лише тижні, що почались не раніше
    /// першого дня людини: тиждень до встановлення застосунку — не «нуль днів із нормою».
    public var goalDaysPerFullWeek: [Int] {
        let monday = today.ordinal - today.weekdayIndex
        let start = firstActive?.ordinal ?? today.ordinal
        return (1...4).compactMap { back -> Int? in
            let from = monday - 7 * back
            guard from >= start else { return nil }
            return (from..<(from + 7)).filter { days[$0]?.goalMet ?? false }.count
        }
    }
}
