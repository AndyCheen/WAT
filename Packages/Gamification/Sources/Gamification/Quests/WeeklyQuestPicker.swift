import Foundation
import Core
import Persistence

/// Входи тижневого пікера (§5): історія — до вчора включно.
public struct WeeklyPickInput: Sendable {
    public var week: WeekKey
    /// 0 — понеділок.
    public var todayIndex: Int
    /// Перший день із порцією — цього тижня.
    public var isFirstWeek: Bool
    public var seed: String
    public var level: Int
    public var dayRhythm: Bool
    /// Днів із нормою в кожному з (до) 4 останніх повних тижнів.
    public var goalDaysPerFullWeek: [Int]
    /// Тижневі минулого тижня: ключ і чи виконано.
    public var lastWeek: [(key: String, isDone: Bool)]
    public var goalDays14: Int
    /// Частка днів із нормою за 4 тижні: у вихідні й у будні.
    public var weekendGoalShare: Double?
    public var weekdayGoalShare: Double?
    /// Скільки з 7 днів вдавалось Д2 — половина до T½.
    public var halfByDays7: Int
    public var weakSpots: QuestWeakSpots
    /// Опора дедлайну Т8 (`nil` — менше 5 днів із нормою за 14).
    public var goalMedianMinute: Int?
    /// Днів за 7 з умовою кожної «Звички» — від них N (WAT-67). Порожньо — N з каталогу.
    public var habitBase: [String: Int]
    public var rules: XPRules

    public init(week: WeekKey, todayIndex: Int, isFirstWeek: Bool, seed: String, level: Int, dayRhythm: Bool,
                goalDaysPerFullWeek: [Int] = [], lastWeek: [(key: String, isDone: Bool)] = [], goalDays14: Int = 0,
                weekendGoalShare: Double? = nil, weekdayGoalShare: Double? = nil, halfByDays7: Int = 0,
                weakSpots: QuestWeakSpots = .init(), goalMedianMinute: Int? = nil, habitBase: [String: Int] = [:],
                rules: XPRules = .default) {
        self.week = week
        self.todayIndex = todayIndex
        self.isFirstWeek = isFirstWeek
        self.seed = seed
        self.level = level
        self.dayRhythm = dayRhythm
        self.goalDaysPerFullWeek = goalDaysPerFullWeek
        self.lastWeek = lastWeek
        self.goalDays14 = goalDays14
        self.weekendGoalShare = weekendGoalShare
        self.weekdayGoalShare = weekdayGoalShare
        self.halfByDays7 = halfByDays7
        self.weakSpots = weakSpots
        self.goalMedianMinute = goalMedianMinute
        self.habitBase = habitBase
        self.rules = rules
    }

    /// Днів до кінця тижня разом із сьогоднішнім.
    public var daysLeft: Int { 7 - todayIndex }
}

/// Вибір тижневих — SPEC-QUESTS §5 дослівно. Чиста функція, хеш — `StableHash`.
public enum WeeklyQuestPicker {
    /// Видаються, лише коли до кінця тижня лишилось стільки днів разом із сьогоднішнім (Пн–Чт).
    public static let minDaysLeft = 4
    static let goalDaysRange = 3...6
    static let runRange = 3...5
    /// Менше днів із нормою за 14 — «Половина норми» замість «Норми».
    static let steadyMinGoalDays14 = 6
    /// Т4 ×2, коли у вихідні норма на стільки рідша, ніж у будні.
    static let weekendGap = 0.25
    /// Т6 ×2, коли Д2 вдавалось рідше.
    static let halfByWeakDays = 3

    public static func pick(_ input: WeeklyPickInput) -> [QuestPick] {
        guard input.daysLeft >= minDaysLeft else { return [] }
        // Запасний день завжди: без «все або нічого» (§5.4).
        let spare = input.daysLeft - 1

        if input.isFirstWeek {
            return [make("weekly.goalDays", count: min(goalDaysRange.lowerBound, spare), input)].compactMap { $0 }
        }
        return [steady(input, spare: spare), habit(input, spare: spare)].compactMap { $0 }
    }

    /// N для Т1 (§5.4).
    static func goalDaysCount(_ input: WeeklyPickInput, spare: Int) -> Int {
        let base = median(input.goalDaysPerFullWeek) ?? goalDaysRange.lowerBound
        var n = clamp(base + 1, goalDaysRange)
        if !input.lastWeek.isEmpty {
            if input.lastWeek.allSatisfy(\.isDone) { n += 1 } else if !input.lastWeek.contains(where: \.isDone) { n -= 1 }
        }
        return min(clamp(n, goalDaysRange), spare)
    }

    private static func steady(_ input: WeeklyPickInput, spare: Int) -> QuestPick? {
        if input.goalDays14 < steadyMinGoalDays14 {
            // Від днів із половиною норми за минулий тиждень + 1 (WAT-67): хто згасає, «Половину норми 4 дні» не брав
            // жодного разу (аудит: 0 з 5).
            let base = input.habitBase["weekly.halfDays"]
            return make("weekly.halfDays", count: base.map { min(max($0 + 1, habitMinCount), spare) } ?? spare, input)
        }
        let goalDays = goalDaysCount(input, spare: spare)
        // Т2: N(Т1) − 2, не більше 5 і запасного дня; менше 3 — не допущене.
        let run = min(goalDays - 2, runRange.upperBound, spare)
        var candidates = [DailyQuestPicker.Candidate]()
        if let pick = make("weekly.goalDays", count: goalDays, input) { candidates.append(.init(pick: pick, weight: 2)) }
        if run >= runRange.lowerBound, let pick = make("weekly.goalRun", count: run, input) {
            candidates.append(.init(pick: pick, weight: 1))
        }
        // Той самий, що минулого тижня, — лише якщо інакше нічого.
        let lastKeys = Set(input.lastWeek.map(\.key))
        let fresh = candidates.filter { !lastKeys.contains($0.pick.key) }
        return DailyQuestPicker.weighted(fresh.isEmpty ? candidates : fresh, hash: "\(input.seed)|\(input.week.rawValue)|steady")
    }

    private static func habit(_ input: WeeklyPickInput, spare: Int) -> QuestPick? {
        let lastKeys = Set(input.lastWeek.map(\.key))
        let candidates = QuestCatalog.definitions(.habit).compactMap { definition -> DailyQuestPicker.Candidate? in
            guard definition.requirements.allows(level: input.level, dayRhythm: input.dayRhythm, remindersActive: true),
                  !lastKeys.contains(definition.key),
                  let count = habitCount(definition, input, spare: spare),
                  let pick = make(definition.key, count: count, input) else { return nil }
            return .init(pick: pick, weight: weight(definition.key, input))
        }
        return DailyQuestPicker.weighted(candidates, hash: "\(input.seed)|\(input.week.rawValue)|habit")
    }

    /// N «Звички» (WAT-67): днів за минулий тиждень з цією умовою + 1, не більше N з каталогу й запасного дня. Хто
    /// має 0 ідеальних днів за тиждень, «3 ідеальних дні» не отримує: аудит 60 днів — 0 з 9. `nil` — не видавати.
    static func habitCount(_ definition: QuestDefinition, _ input: WeeklyPickInput, spare: Int) -> Int? {
        let full = min(definition.baseCount ?? spare, spare)
        guard definition.key != "weekly.weekend", let base = input.habitBase[definition.key] else { return full }
        if case .daysCount(.allBlocks) = definition.condition, base == 0 { return nil }
        return min(max(base + 1, habitMinCount), full)
    }

    static let habitMinCount = 2

    private static func weight(_ key: String, _ input: WeeklyPickInput) -> Int {
        switch key {
        case "weekly.wakeGlassDays": return input.weakSpots.lateFirstGlass ? 2 : 1
        case "weekly.goalByDays": return input.weakSpots.lateGoal ? 2 : 1
        case "weekly.weekend":
            guard let weekend = input.weekendGoalShare, let weekday = input.weekdayGoalShare else { return 1 }
            return weekday - weekend >= weekendGap ? 2 : 1
        case "weekly.halfByDays": return input.halfByDays7 < halfByWeakDays ? 2 : 1
        default: return 1
        }
    }

    /// Пік із N — і для `--quests`, повз відбір.
    static func make(_ key: String, count: Int, _ input: WeeklyPickInput) -> QuestPick? {
        guard let definition = QuestCatalog.definition(key), let rule = definition.difficulty else { return nil }
        let difficulty = rule.difficulty(count: count)
        let anchor: Int? = if case .daysCount(.shareBy(_, .personalGoal)) = definition.condition {
            input.goalMedianMinute
        } else {
            nil
        }
        return QuestPick(key: key, difficulty: difficulty, rewardXp: input.rules.questXp(scope: .weekly, difficulty: difficulty),
                         deadlineMinute: anchor, count: count)
    }

    /// Медіана цілих — нижня з двох середніх: N не має рости від одного вдалого тижня з двох.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
