import Foundation
import Core
import Persistence

/// Числа несподіваних (SPEC-QUESTS §6.1, §6.3).
public enum SurpriseRules {
    /// Аудит першого тижня: дні 4, 6 і 7 уже впираються в ліміт 8 сповіщень.
    public static let firstDay = 8
    /// Відступ після двох проігнорованих поспіль — не частіше ніж раз на 14 днів (SPEC-NOTIFICATIONS §10.3).
    static let backoffDays = 14
    /// Скільки днів історії бачить пікер: Н2 рахує виконані Н1 за 28 днів.
    public static let historyDays = 28
    static let glassNowDoneForBlock = 2
    /// Найраніша поява — W + 60 хв; кінець вікна — не пізніше Z − 2 год (§0, п. 4: нічого за 2 год до сну).
    static let earliestAfterWake = 60
    public static let latestEndBeforeSleep = 120
    /// Людина мусить з'явитися щонайменше за 15 хв до появи: несподіване планується в першу дію дня (§6.1).
    static let leadMinutes = 15
    /// Н1 — через 30 хв після початку блоку, на годину.
    static let glassNowOffset = 30
    static let glassNowWindow = 60
    /// Н4 — хеш-хвилина в [W + 2 год, Z − 3 год] із кроком 5 хв, на 15 хв.
    static let flashFromWake = 120
    static let flashBeforeSleep = 180
    static let flashStep = 5
    static let flashWindow = 15
    /// Н2 і Н3 тягнуться до кінця блоку чи дня: коротше за годину після зсуву тихим періодом — не видаються.
    static let minLongWindow = 60
}

/// Сигнали прогалин (§6.2) — `Insights` за даними до вчора включно, тож стабільні протягом дня. Рахує й приносить
/// `AppServices`: `Gamification` не імпортує `Insights`.
public struct SurpriseSignals: Sendable, Equatable {
    /// Слабка частина доби за 14 днів — `GoalBlock.deadlinePart.key` її блоку.
    public var weakPartKey: String?
    /// Слабкий день тижня за 42 дні, 0 — понеділок.
    public var weakWeekday: Int?

    public init(weakPartKey: String? = nil, weakWeekday: Int? = nil) {
        self.weakPartKey = weakPartKey
        self.weakWeekday = weakWeekday
    }

    public static let none = SurpriseSignals()

    var hasGaps: Bool { weakPartKey != nil || weakWeekday != nil }
}

/// Несподіване з історії — для лімітів, «не поспіль», відступу й Н2.
public struct SurpriseRecord: Sendable, Equatable {
    public let day: DayKey
    public let key: String
    public let state: QuestState
    public let blockIndex: Int?

    public init(day: DayKey, key: String, state: QuestState, blockIndex: Int? = nil) {
        self.day = day
        self.key = key
        self.state = state
        self.blockIndex = blockIndex
    }

    /// Скасоване до появи людина не бачила — воно не рахується ні в ліміт, ні в «поспіль», ні у відступ.
    var wasShown: Bool { state != .cancelled }
    /// Минуле активне так і не оцінили після кінця вікна — теж проігноровано.
    var wasIgnored: Bool { state == .expired || state == .active }
}

/// Входи `SurprisePicker` (QUESTS-PLAN §3.4). Збирає `GamificationService` у першу дію дня.
public struct SurprisePickInput: Sendable {
    public var day: DayKey
    public var week: WeekKey
    /// День людини (§4.1).
    public var dayNumber: Int
    public var seed: String
    /// Налаштування «Несподівані завдання»: 0, 1 чи 2 на тиждень.
    public var perWeek: Int
    public var dayRhythm: Bool
    public var schedule: DaySchedule
    public var goalMl: Int
    /// Хвилина першої дії дня — мить видачі.
    public var issueMinute: Int
    public var goalMetToday: Bool
    /// Несподівані за `SurpriseRules.historyDays` днів до вчора включно, будь-які стани.
    public var history: [SurpriseRecord]
    public var signals: SurpriseSignals
    /// Увімкнені тихі періоди цього дня тижня, у хвилинах доби.
    public var quietMinutes: [Range<Int>]
    /// Щоденні, видані сьогодні, — «не повторює щоденне» (§6.3). Ставить `QuestEngine` після їхньої видачі.
    public var dailyKeys: [String]
    /// Блок Д7, якщо його видано сьогодні.
    public var dailyBlockIndex: Int?
    public var rules: XPRules

    public init(day: DayKey, week: WeekKey, dayNumber: Int, seed: String, perWeek: Int, dayRhythm: Bool,
                schedule: DaySchedule, goalMl: Int, issueMinute: Int, goalMetToday: Bool = false,
                history: [SurpriseRecord] = [], signals: SurpriseSignals = .none, quietMinutes: [Range<Int>] = [],
                dailyKeys: [String] = [], dailyBlockIndex: Int? = nil, rules: XPRules = .default) {
        self.day = day
        self.week = week
        self.dayNumber = dayNumber
        self.seed = seed
        self.perWeek = perWeek
        self.dayRhythm = dayRhythm
        self.schedule = schedule
        self.goalMl = goalMl
        self.issueMinute = issueMinute
        self.goalMetToday = goalMetToday
        self.history = history
        self.signals = signals
        self.quietMinutes = quietMinutes
        self.dailyKeys = dailyKeys
        self.dailyBlockIndex = dailyBlockIndex
        self.rules = rules
    }

    var blocks: [GoalBlock] { schedule.curve(goalMl: goalMl).goalBlocks() }
}

/// Вибір несподіваного — SPEC-QUESTS §6.1–6.3 дослівно. Чиста функція: той самий вхід — той самий вибір, хеш —
/// `StableHash`. Планує лише на сьогодні: вихід — завдання з хвилиною появи й кінцем вікна.
public enum SurprisePicker {
    static let glassNow = "surprise.glassNow"
    static let closeBlock = "surprise.closeBlock"
    static let weekday = "surprise.weekday"
    static let flash = "surprise.flash"

    public static func pick(_ input: SurprisePickInput) -> QuestPick? {
        guard input.perWeek > 0, input.dayNumber >= SurpriseRules.firstDay, !input.goalMetToday else { return nil }

        let shown = input.history.filter { $0.day < input.day && $0.wasShown }.sorted { $0.day < $1.day }
        let monday = input.day.ordinal - input.day.weekdayIndex
        let thisWeek = shown.filter { $0.day.ordinal >= monday }.count
        // Без прогалин — щонайбільше одне на тиждень, і лише «азарт» (§6.1).
        let limit = input.signals.hasGaps ? input.perWeek : 1
        guard thisWeek < limit,
              shown.last?.day.ordinal != input.day.ordinal - 1,
              !isBackingOff(shown, today: input.day) else { return nil }

        let isWeakDay = input.signals.weakWeekday == input.day.weekdayIndex
        guard isWeakDay || candidateDays(input, limit: limit).contains(input.day.weekdayIndex) else { return nil }

        for key in kinds(input, isWeakDay: isWeakDay, thisWeek: thisWeek) {
            if let pick = make(key, input) { return pick }
        }
        return nil
    }

    /// Два проігноровані поспіль — не частіше ніж раз на 14 днів, доки одне не виконано.
    static func isBackingOff(_ shown: [SurpriseRecord], today: DayKey) -> Bool {
        guard shown.count >= 2, shown.suffix(2).allSatisfy(\.wasIgnored), let last = shown.last else { return false }
        return today.ordinal - last.day.ordinal < SurpriseRules.backoffDays
    }

    /// Дні тижня-кандидати від хеша тижня (§6.3): для двох — `d1` і ще один не поруч, бо зсув 2…5.
    static func candidateDays(_ input: SurprisePickInput, limit: Int) -> [Int] {
        let hash = StableHash.fnv1a("\(input.seed)|\(input.week.rawValue)|surprise")
        let first = Int(hash % 7)
        guard limit > 1 else { return [first] }
        return [first, (first + 2 + Int((hash / 7) % 4)) % 7]
    }

    /// Вид за сигналом (§6.2) — від бажаного до запасного: Н2 не влізло в день — Н1.
    private static func kinds(_ input: SurprisePickInput, isWeakDay: Bool, thisWeek: Int) -> [String] {
        if isWeakDay {
            // Н3 повторило б «Норму до {T}» сьогоднішнього «Темпу» — тоді несподіваного цього дня немає.
            return input.dailyKeys.contains("daily.goalBy") ? [] : [weekday]
        }
        if let part = input.signals.weakPartKey {
            guard let block = input.blocks.firstIndex(where: { $0.deadlinePart.key == part }) else { return [] }
            let glassesDone = input.history.filter {
                $0.key == glassNow && $0.state == .completed && $0.blockIndex == block
            }.count
            // Н2 не видається, якщо сьогодні Д7 на той самий блок.
            let closes = input.dayRhythm && glassesDone >= SurpriseRules.glassNowDoneForBlock
                && input.dailyBlockIndex != block
            return closes ? [closeBlock, glassNow] : [glassNow]
        }
        return input.signals.hasGaps || thisWeek > 0 ? [] : [flash]
    }

    /// Хвилина й вікно (§6.3) з межами для всіх: не раніше W + 60, кінець не пізніше Z − 2 год, поза тихими
    /// періодами (зсув уперед), і людина з'явилась щонайменше за 15 хв до появи.
    private static func make(_ key: String, _ input: SurprisePickInput) -> QuestPick? {
        let wake = input.schedule.wakeMinutes
        let latestEnd = input.schedule.sleepMinutes - SurpriseRules.latestEndBeforeSleep
        guard let window = nominal(key, input) else { return nil }
        var start = max(window.start, wake + SurpriseRules.earliestAfterWake)
        while let quiet = input.quietMinutes.first(where: { $0.contains(start) }) { start = quiet.upperBound }
        // Короткі вікна зсуваються цілком, довгі тягнуться до свого кінця.
        let end = window.length.map { start + $0 } ?? min(window.end, latestEnd)
        guard end <= latestEnd, window.length != nil || end - start >= SurpriseRules.minLongWindow,
              input.issueMinute <= start - SurpriseRules.leadMinutes else { return nil }
        return resolve(key, start: start, end: end, block: window.block, input)
    }

    private struct Window {
        let start: Int
        let end: Int
        /// Фіксована довжина (Н1, Н4); `nil` — до кінця `end`.
        let length: Int?
        let block: Int?
    }

    private static func nominal(_ key: String, _ input: SurprisePickInput) -> Window? {
        let blocks = input.blocks
        let block = input.signals.weakPartKey.flatMap { part in blocks.firstIndex { $0.deadlinePart.key == part } }
        switch key {
        case glassNow:
            guard let block else { return nil }
            let start = blocks[block].fromMinute + SurpriseRules.glassNowOffset
            return Window(start: start, end: start + SurpriseRules.glassNowWindow,
                          length: SurpriseRules.glassNowWindow, block: block)
        case closeBlock:
            guard let block else { return nil }
            return Window(start: blocks[block].fromMinute, end: blocks[block].toMinute, length: nil, block: block)
        case weekday:
            return Window(start: input.schedule.wakeMinutes + SurpriseRules.earliestAfterWake,
                          end: input.schedule.sleepMinutes - SurpriseRules.latestEndBeforeSleep, length: nil, block: nil)
        case flash:
            let from = input.schedule.wakeMinutes + SurpriseRules.flashFromWake
            let to = input.schedule.sleepMinutes - SurpriseRules.flashBeforeSleep
            guard to >= from else { return nil }
            let steps = UInt64((to - from) / SurpriseRules.flashStep + 1)
            let hash = StableHash.fnv1a("\(input.seed)|\(input.day.rawValue)|flash")
            let start = from + Int(hash % steps) * SurpriseRules.flashStep
            return Window(start: start, end: start + SurpriseRules.flashWindow, length: SurpriseRules.flashWindow,
                          block: nil)
        default:
            return nil
        }
    }

    /// Параметри без відбору — і для `--quests surprise:…`: там хвилину появи задає прапорець, а кінець і блок —
    /// ті самі правила, що в пікера.
    static func resolve(_ key: String, start: Int, end: Int? = nil, block: Int? = nil,
                        _ input: SurprisePickInput) -> QuestPick? {
        guard let definition = QuestCatalog.definition(key), definition.scope == .adhoc,
              let difficulty = definition.difficulty?.difficulty(count: nil) else { return nil }
        let blocks = input.blocks
        let blockIndex: Int?
        switch key {
        case glassNow, closeBlock:
            blockIndex = block ?? blocks.lastIndex { $0.fromMinute <= start } ?? 0
        default:
            blockIndex = nil
        }
        let latestEnd = input.schedule.sleepMinutes - SurpriseRules.latestEndBeforeSleep
        let resolvedEnd: Int
        switch key {
        case glassNow: resolvedEnd = end ?? start + SurpriseRules.glassNowWindow
        case flash: resolvedEnd = end ?? start + SurpriseRules.flashWindow
        case closeBlock: resolvedEnd = end ?? blockIndex.map { min(blocks[$0].toMinute, latestEnd) } ?? latestEnd
        default: resolvedEnd = end ?? latestEnd
        }
        return QuestPick(
            key: key, difficulty: difficulty, rewardXp: input.rules.questXp(scope: .adhoc, difficulty: difficulty),
            deadlineMinute: resolvedEnd, blockIndex: blockIndex, startMinute: start,
            weekdayIndex: key == weekday ? input.day.weekdayIndex : nil
        )
    }
}
