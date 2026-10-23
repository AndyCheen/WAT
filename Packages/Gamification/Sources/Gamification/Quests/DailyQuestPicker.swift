import Foundation
import Core
import Persistence

/// Вибране завдання з резолвленими параметрами — те, що пишеться в `QuestInstance`.
public struct QuestPick: Sendable, Equatable {
    public let key: String
    public var difficulty: QuestDifficulty
    public var rewardXp: Int
    /// Щоденні — T дня; тижневе Т8 — опорна медіана закриття норми (дедлайн кожного дня — з його розкладу).
    public var deadlineMinute: Int?
    public var blockIndex: Int?
    public var count: Int?
    /// Несподіване: хвилина появи (`deadlineMinute` — кінець вікна).
    public var startMinute: Int?
    /// Н3 — день тижня, 0 — понеділок.
    public var weekdayIndex: Int?

    public init(key: String, difficulty: QuestDifficulty, rewardXp: Int, deadlineMinute: Int? = nil,
                blockIndex: Int? = nil, count: Int? = nil, startMinute: Int? = nil, weekdayIndex: Int? = nil) {
        self.key = key
        self.difficulty = difficulty
        self.rewardXp = rewardXp
        self.deadlineMinute = deadlineMinute
        self.blockIndex = blockIndex
        self.count = count
        self.startMinute = startMinute
        self.weekdayIndex = weekdayIndex
    }
}

/// Найслабший блок цілі за 14 днів (Д7): індекс і медіана «випито в блоці / ціль». Медіани немає — історії
/// в блоці ще немає.
public struct WeakBlock: Sendable, Equatable {
    public let index: Int
    public let median: Double?

    public init(index: Int, median: Double?) {
        self.index = index
        self.median = median
    }
}

/// Слабкі місця людини за історією до вчора — ваги ×2 (§4.5, §5.6).
public struct QuestWeakSpots: Sendable, Equatable {
    /// Медіана першої порції пізніше за W + 90 хв.
    public var lateFirstGlass = false
    /// Норма закривається пізніше за Z − 2 год або менше 4 днів із 7.
    public var lateGoal = false

    public init(lateFirstGlass: Bool = false, lateGoal: Bool = false) {
        self.lateFirstGlass = lateFirstGlass
        self.lateGoal = lateGoal
    }
}

/// Входи щоденного пікера (§4.1): усе з історії — до вчора включно, тож вибір стабільний протягом дня.
public struct DailyPickInput: Sendable {
    public var day: DayKey
    /// Від першого дня з порцією; до першої порції — 1.
    public var dayNumber: Int
    public var seed: String
    public var level: Int
    public var dayRhythm: Bool
    public var remindersActive: Bool
    public var schedule: DaySchedule
    public var goalMl: Int
    public var glassMl: Int
    public var issueMinute: Int
    public var goalMetYesterday: Bool
    public var goalDays7: Int
    /// Ключі щоденних учора — «не вчорашнє» (§4.2, п. 2).
    public var yesterdayKeys: Set<String>
    /// Ключі щоденних за 6 днів до вчора включно, з повторами: разом із сьогоднішнім — «останні 7 днів»
    /// правила «≤ 2 за 7 днів» (§4.2, п. 3).
    public var recentKeys: [String]
    /// Медіана хвилини закриття норми за 14 днів; `nil` — менше 5 днів із нормою.
    public var goalMedianMinute: Int?
    public var weakSpots: QuestWeakSpots
    public var weakBlock: WeakBlock?
    public var rules: XPRules

    public init(day: DayKey, dayNumber: Int, seed: String, level: Int, dayRhythm: Bool, remindersActive: Bool,
                schedule: DaySchedule, goalMl: Int, glassMl: Int, issueMinute: Int, goalMetYesterday: Bool = true,
                goalDays7: Int = 0, yesterdayKeys: Set<String> = [], recentKeys: [String] = [],
                goalMedianMinute: Int? = nil, weakSpots: QuestWeakSpots = .init(), weakBlock: WeakBlock? = nil,
                rules: XPRules = .default) {
        self.day = day
        self.dayNumber = dayNumber
        self.seed = seed
        self.level = level
        self.dayRhythm = dayRhythm
        self.remindersActive = remindersActive
        self.schedule = schedule
        self.goalMl = goalMl
        self.glassMl = glassMl
        self.issueMinute = issueMinute
        self.goalMetYesterday = goalMetYesterday
        self.goalDays7 = goalDays7
        self.yesterdayKeys = yesterdayKeys
        self.recentKeys = recentKeys
        self.goalMedianMinute = goalMedianMinute
        self.weakSpots = weakSpots
        self.weakBlock = weakBlock
        self.rules = rules
    }
}

/// Вибір щоденних — SPEC-QUESTS §4 дослівно. Чиста функція: той самий вхід — той самий вибір, хеш — `StableHash`.
public enum DailyQuestPicker {
    /// Складні — лише з цією кількістю днів норми з 7 (§4.3).
    static let hardMinGoalDays = 5
    static let pairBudget = 4
    /// Після дня без норми — лише легкі, сума ≤ 2: важкий день не зустрічаємо подвійним тиском.
    static let gentleBudget = 2
    /// Не частіше: ≤ 2 рази за 7 днів (§4.2, п. 3) — разом із сьогоднішнім.
    static let maxRecentRepeats = 2
    /// Сім днів правила разом із сьогоднішнім: учора й ще 5 днів до нього.
    public static let recentDays = 6
    /// День 1 пізніше за Z − 4 год — лише «Перша склянка» (§3.3).
    static let lateFirstDayMinutes = 240
    /// Д6: N = G / P у межах 3…5.
    static let glassesRange = 3...5
    /// Д7 ×2, коли медіана блоку нижча.
    static let weakBlockMedian = 0.7

    public static func pick(_ input: DailyPickInput) -> [QuestPick] {
        if input.dayNumber <= 2 { return starter(input) }

        let gentle = !input.goalMetYesterday
        let budget = gentle ? gentleBudget : pairBudget
        let hardest: QuestDifficulty = gentle ? .easy : (input.goalDays7 >= hardMinGoalDays ? .hard : .medium)
        let admissible = { (slot: [QuestDefinition]) in
            slot.compactMap { candidate($0, input) }.filter { $0.pick.difficulty <= hardest }
        }

        // Правило «≤ 2 за 7 днів» знімається, коли слот лишається порожнім, — але не на легкому дні: там пул і так
        // з одного-двох легких, і краще одне завдання, ніж те саме втретє за тиждень (рішення від 22.10.2026).
        let relaxes = !gentle

        // «Просто норма» (WAT-42): одне завдання з «Темпу» й тих «Ритму», що не про частини доби.
        guard input.dayRhythm else {
            let pool = QuestCatalog.definitions(.tempo) + QuestCatalog.definitions(.rhythm).filter { !$0.isDayPartQuest }
            return choose(admissible(pool), salt: "single", input, relaxes: relaxes).map { [$0] } ?? []
        }

        let rhythm = admissible(QuestCatalog.definitions(.rhythm))
        // «Темп» обирається першим, але так, щоб «Ритму» лишилось на найлегше з тих, що він справді візьме: інакше
        // складне в «Темпі» змушувало б «Ритм» знімати правило повторів.
        let rhythmFloor = usable(rhythm, input, relaxes: relaxes).map(\.pick.difficulty.rawValue).min() ?? 0
        let tempo = admissible(QuestCatalog.definitions(.tempo))
            .filter { $0.pick.difficulty.rawValue + rhythmFloor <= budget }
        let tempoPick = choose(tempo, salt: "tempo", input, relaxes: relaxes)
        let left = budget - (tempoPick?.difficulty.rawValue ?? 0)
        let rhythmPick = choose(rhythm.filter { $0.pick.difficulty.rawValue <= left }, salt: "rhythm", input,
                                relaxes: relaxes)
        return [tempoPick, rhythmPick].compactMap { $0 }
    }

    // MARK: - Стартові дні (§3.3)

    private static func starter(_ input: DailyPickInput) -> [QuestPick] {
        let picks: [QuestPick]
        if input.dayNumber == 1 {
            let late = input.issueMinute > input.schedule.sleepMinutes - lateFirstDayMinutes
            picks = (late ? ["starter.firstGlass"] : ["starter.firstGlass", "starter.halfGoal"]).compactMap { fixed($0, input) }
            // Без «Ритму дня» — одне: перший крок, з якого все починається.
            return input.dayRhythm ? picks : Array(picks.prefix(1))
        }
        // День 2: Д5 + С3; дедлайн Д5 уже близько чи минув — Д6. Без «Ритму дня» — лише перша повна норма:
        // вона й є головне, що завдання мають зрушити.
        let goal = fixed("starter.firstGoal", input)
        guard input.dayRhythm else { return [goal].compactMap { $0 } }
        let rhythm = fixed("daily.wakeGlass", input) ?? fixed("daily.glasses", input)
        return [rhythm, goal].compactMap { $0 }
    }

    private static func fixed(_ key: String, _ input: DailyPickInput) -> QuestPick? {
        QuestCatalog.definition(key).flatMap { candidate($0, input, fresh: false)?.pick }
    }

    // MARK: - Відбір і вибір

    struct Candidate {
        let pick: QuestPick
        let weight: Int
    }

    /// Допущене завдання з резолвленими параметрами (§4.2, §4.4) і вагою (§4.5). Правило «≤ 2 за 7 днів» —
    /// у `choose`: воно знімається, лише коли слот лишається порожнім.
    ///
    /// - Parameter fresh: правило «не вчорашнє». Стартові його не мають: хто вчора нічого не записав, той знову
    ///   в дні 1 і знову отримує «Першу склянку».
    static func candidate(_ definition: QuestDefinition, _ input: DailyPickInput, fresh: Bool = true) -> Candidate? {
        guard case .day(let condition) = definition.condition, definition.difficulty != nil,
              definition.requirements.allows(level: input.level, dayRhythm: input.dayRhythm,
                                             remindersActive: input.remindersActive),
              !fresh || !input.yesterdayKeys.contains(definition.key),
              condition != .blockReached || input.weakBlock != nil else { return nil }
        let pick = resolve(definition, input)
        if let deadline = pick.deadlineMinute, deadline - input.issueMinute < definition.minLeadMinutes { return nil }
        return Candidate(pick: pick, weight: weight(definition.key, input))
    }

    /// Параметри завдання на цей день — T, N, блок, складність і XP — без відбору. Окремо від `candidate`, бо
    /// `--quests` видає завдання повз правила.
    static func resolve(_ definition: QuestDefinition, _ input: DailyPickInput) -> QuestPick {
        let condition = definition.condition.dayCondition
        var params = QuestParams(goalMedianMinute: input.goalMedianMinute, glassMl: input.glassMl)
        if condition == .blockReached { params.blockIndex = input.weakBlock?.index ?? 0 }
        switch condition {
        case .glasses(_, nil)?:
            params.count = min(max(input.goalMl / max(1, input.glassMl), glassesRange.lowerBound), glassesRange.upperBound)
        case .glasses?:
            params.count = definition.baseCount
        default:
            break
        }
        let today = QuestDay(day: input.day, goalMl: input.goalMl, schedule: input.schedule, portions: [])
        let difficulty = definition.difficulty?.difficulty(count: params.count) ?? .easy
        return QuestPick(key: definition.key, difficulty: difficulty,
                         rewardXp: input.rules.questXp(scope: .daily, difficulty: difficulty),
                         deadlineMinute: condition?.deadline(on: today, params: params),
                         blockIndex: params.blockIndex, count: params.count)
    }

    private static func weight(_ key: String, _ input: DailyPickInput) -> Int {
        switch key {
        case "daily.wakeGlass", "daily.quarterBy": return input.weakSpots.lateFirstGlass ? 2 : 1
        case "daily.goalBy", "daily.threeQuartersBy": return input.weakSpots.lateGoal ? 2 : 1
        case "daily.closeBlock": return (input.weakBlock?.median ?? 1) < weakBlockMedian ? 2 : 1
        default: return 1
        }
    }

    private static func choose(_ candidates: [Candidate], salt: String, _ input: DailyPickInput,
                               relaxes: Bool) -> QuestPick? {
        weighted(usable(candidates, input, relaxes: relaxes), hash: "\(input.seed)|\(input.day.rawValue)|\(salt)")
    }

    /// Ті, що пройшли «≤ 2 за 7 днів», а коли таких немає — усі (якщо правило можна зняти).
    private static func usable(_ candidates: [Candidate], _ input: DailyPickInput, relaxes: Bool) -> [Candidate] {
        let fresh = candidates.filter { candidate in
            input.recentKeys.filter { $0 == candidate.pick.key }.count < maxRecentRepeats
        }
        return fresh.isEmpty && relaxes ? candidates : fresh
    }

    /// Зважений цілочисельний вибір: `hash % Σваг` (§4.6). Порядок — каталогу, тож результат стабільний.
    static func weighted(_ candidates: [Candidate], hash key: String) -> QuestPick? {
        let total = candidates.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var roll = Int(StableHash.fnv1a(key) % UInt64(total))
        for candidate in candidates {
            if roll < candidate.weight { return candidate.pick }
            roll -= candidate.weight
        }
        return candidates.last?.pick
    }
}
