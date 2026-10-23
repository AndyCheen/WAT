import Foundation
import Core
import Persistence
import Metrics

/// Ціль архівного завдання: фіксована або привʼязана до денної норми.
public enum QuestTarget: Sendable, Equatable {
    case fixed(Double)
    case dailyGoal
    case dailyGoalFraction(Double)

    public func resolve(dailyGoalMl: Int) -> Double {
        switch self {
        case .fixed(let value): return value
        case .dailyGoal: return Double(dailyGoalMl)
        case .dailyGoalFraction(let f): return Double(dailyGoalMl) * f
        }
    }
}

/// Слот видачі (SPEC-QUESTS §2): щоденні — «Темп» (скільки до котрої) і «Ритм» (як розподілено), тижневі —
/// «Сталість» (дні з нормою) і «Звичка» (дні з умовою).
public enum QuestSlot: String, Sendable, CaseIterable {
    case tempo, rhythm, starter, steady, habit, surprise
}

/// Складність → XP (`XPRules.questXp`). Raw зберігається на інстансі.
public enum QuestDifficulty: Int, Sendable, Comparable, CaseIterable {
    case easy = 1, medium, hard

    public static func < (lhs: QuestDifficulty, rhs: QuestDifficulty) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Складність фіксована або від N (Т1, Т2): N ≥ `hard` — складне, N ≥ `medium` — середнє.
public enum QuestDifficultyRule: Sendable, Equatable {
    case fixed(QuestDifficulty)
    case byCount(medium: Int, hard: Int)

    public func difficulty(count: Int?) -> QuestDifficulty {
        switch self {
        case .fixed(let difficulty): return difficulty
        case let .byCount(medium, hard):
            let n = count ?? 0
            return n >= hard ? .hard : (n >= medium ? .medium : .easy)
        }
    }
}

/// Вимоги з §3: без «Ритму дня» — нічого про частини доби, без нагадувань — нічого про нагадування.
public struct QuestRequirements: Sendable, Equatable {
    public var dayRhythm = false
    public var reminders = false
    public var minLevel = 1

    public init(dayRhythm: Bool = false, reminders: Bool = false, minLevel: Int = 1) {
        self.dayRhythm = dayRhythm
        self.reminders = reminders
        self.minLevel = minLevel
    }

    public func allows(level: Int, dayRhythm rhythmOn: Bool, remindersActive: Bool) -> Bool {
        level >= minLevel && (!dayRhythm || rhythmOn) && (!reminders || remindersActive)
    }

    public static let none = QuestRequirements()
}

/// Іменник при N — форму за числом обирає `Features` (`Plural`).
public enum QuestNoun: Sendable, Equatable {
    /// «3 склянки», «5 склянок».
    case glasses
    /// «3 дні», «5 днів».
    case days
    /// «3 ранки», «5 ранків».
    case mornings
    /// «2 ідеальні дні», «5 ідеальних днів».
    case perfectDays
}

/// Назва завдання — шаблон без готового рядка: час і одиниці форматує `Features` (`QuestPresenter`), значення
/// T, N і блоку — в знімку. Так назва в унціях і 12-годинному форматі не потребує окремого каталогу.
public struct QuestTitle: Sendable, Equatable {
    public enum Part: Sendable, Equatable, ExpressibleByStringLiteral {
        case text(String)
        /// T — `QuestSnapshot.deadlineMinute`.
        case time
        /// N — `QuestSnapshot.count` з узгодженим іменником.
        case count(QuestNoun)
        /// Об'єм у системі людини: «150 мл» / «5 унц.».
        case volume(Int)
        /// Блок — «ранок / день / вечір» (`QuestSnapshot.blockIndex` з `blockCount`).
        case block
        /// День тижня в називному — «Субота» (`QuestSnapshot.weekdayIndex`, Н3).
        case weekday

        public init(stringLiteral value: String) { self = .text(value) }
    }

    public let parts: [Part]

    public init(_ parts: Part...) { self.parts = parts }
}

public struct QuestDefinition: Sendable, Identifiable {
    public let key: String
    public let scope: QuestScope
    /// `nil` — архівне.
    public let slot: QuestSlot?
    public let title: QuestTitle
    public let condition: QuestCondition
    /// `nil` — архівне: XP з `legacyXp`.
    public let difficulty: QuestDifficultyRule?
    public let requirements: QuestRequirements
    /// Скільки хвилин від видачі до дедлайну потрібно, щоб завдання видати (§4.2, п. 4).
    public let minLeadMinutes: Int
    /// N за замовчуванням для тижневих «Звички» (§3.5); для решти N рахує пікер.
    public let baseCount: Int?
    /// XP інстансів до WAT-63: у них немає `rewardXp`.
    public let legacyXp: Int
    public let isRetired: Bool

    public var id: String { key }

    public init(
        key: String, scope: QuestScope, slot: QuestSlot?, title: QuestTitle, condition: QuestCondition,
        difficulty: QuestDifficultyRule?, requirements: QuestRequirements = .none,
        minLeadMinutes: Int = QuestCatalog.defaultLeadMinutes, baseCount: Int? = nil,
        legacyXp: Int = 0, isRetired: Bool = false
    ) {
        self.key = key
        self.scope = scope
        self.slot = slot
        self.title = title
        self.condition = condition
        self.difficulty = difficulty
        self.requirements = requirements
        self.minLeadMinutes = minLeadMinutes
        self.baseCount = baseCount
        self.legacyXp = legacyXp
        self.isRetired = isRetired
    }

    /// Завдання на частини доби: у режимі «просто норма» не видається (WAT-42, §28).
    public var isDayPartQuest: Bool {
        if requirements.dayRhythm { return true }
        guard case .legacy(let rule, _) = condition, case .metric(let key, _, _) = rule.source else { return false }
        return MetricKey.dayParts.contains(key)
    }

    /// Як показати прогрес: «ще N мл», «2/4» чи «2/5 дн.».
    public var kind: QuestKind {
        switch condition {
        case .day(let condition): return condition.measuresVolume ? .volume : .count
        case .daysCount, .daysRun, .weekend: return .days
        case .legacy(let rule, let target):
            if scope == .weekly { return .days }
            return rule.measuresVolume || target == .dailyGoal ? .volume : .count
        }
    }
}

public enum QuestKind: Sendable, Equatable {
    case volume, count, days
}

/// Каталог завдань — SPEC-QUESTS §3 (рішення від 20.10.2026). **Ключі не міняти після релізу**: на них історія
/// ротації («не вчорашнє», «≤ 2 за 7 днів») і «Звичка», що не повторює минулий тиждень.
public enum QuestCatalog {
    /// §4.2, п. 4: до дедлайну після видачі — щонайменше година.
    public static let defaultLeadMinutes = 60

    private static let rhythm = QuestRequirements(dayRhythm: true)

    /// §3.1 «Темп» — драбина «позначка до часу».
    public static let tempo: [QuestDefinition] = [
        .init(key: "daily.quarterBy", scope: .daily, slot: .tempo, title: .init("Чверть норми до ", .time),
              condition: .day(.shareBy(0.25, .wakePlus(minutes: 180))), difficulty: .fixed(.easy)),
        .init(key: "daily.halfBy", scope: .daily, slot: .tempo, title: .init("Половина до ", .time),
              condition: .day(.shareBy(0.5, .curveShare(0.5))), difficulty: .fixed(.medium)),
        .init(key: "daily.threeQuartersBy", scope: .daily, slot: .tempo, title: .init("¾ норми до ", .time),
              condition: .day(.shareBy(0.75, .curveShare(0.75))), difficulty: .fixed(.medium)),
        .init(key: "daily.goalBy", scope: .daily, slot: .tempo, title: .init("Норма до ", .time),
              condition: .day(.shareBy(1, .personalGoal)), difficulty: .fixed(.medium)),
        .init(key: "daily.goalNoReminders", scope: .daily, slot: .tempo, title: .init("Норма без нагадувань"),
              condition: .day(.goalAhead), difficulty: .fixed(.hard),
              requirements: .init(reminders: true, minLevel: 5))
    ]

    /// §3.2 «Ритм» — як розподілено.
    public static let rhythmSlot: [QuestDefinition] = [
        // Дедлайн — година після підйому, тож правило «година до дедлайну» з'їло б його в кожного, хто відкриває
        // застосунок після підйому (PLAN.md п. 23 — так уже не видавалось «Випити воду зранку»). Одна склянка —
        // хвилинна справа: досить 20 хв (рішення від 22.10.2026).
        .init(key: "daily.wakeGlass", scope: .daily, slot: .rhythm, title: .init("Склянка після підйому"),
              condition: .day(.wakeGlass(withinMinutes: 60)), difficulty: .fixed(.easy), minLeadMinutes: 20),
        .init(key: "daily.glasses", scope: .daily, slot: .rhythm,
              title: .init(.count(.glasses), " від ", .volume(QuestRules.glassMinMl)),
              condition: .day(.glasses(minMl: QuestRules.glassMinMl, deadline: nil)), difficulty: .fixed(.easy)),
        .init(key: "daily.glassesBy", scope: .daily, slot: .rhythm, title: .init(.count(.glasses), " до ", .time),
              condition: .day(.glasses(minMl: QuestRules.glassMinMl, deadline: .curveShare(0.5))),
              difficulty: .fixed(.medium), baseCount: 3),
        .init(key: "daily.closeBlock", scope: .daily, slot: .rhythm, title: .init("Закрий ", .block),
              condition: .day(.blockReached), difficulty: .fixed(.medium), requirements: rhythm),
        .init(key: "daily.everyBlock", scope: .daily, slot: .rhythm, title: .init("Вода в кожній частині"),
              condition: .day(.portionInEachBlock(minMl: QuestRules.glassMinMl)), difficulty: .fixed(.easy),
              requirements: rhythm),
        .init(key: "daily.allBlocks", scope: .daily, slot: .rhythm, title: .init("Три частини з трьох"),
              condition: .day(.allBlocks), difficulty: .fixed(.hard),
              requirements: .init(dayRhythm: true, minLevel: 5))
    ]

    /// §3.3 — дні 1–2 людини.
    public static let starter: [QuestDefinition] = [
        .init(key: "starter.firstGlass", scope: .daily, slot: .starter, title: .init("Перша склянка"),
              condition: .day(.anyPortion), difficulty: .fixed(.easy)),
        .init(key: "starter.halfGoal", scope: .daily, slot: .starter, title: .init("Половина норми"),
              condition: .day(.halfGoal), difficulty: .fixed(.easy)),
        .init(key: "starter.firstGoal", scope: .daily, slot: .starter, title: .init("Перша повна норма"),
              condition: .day(.goal), difficulty: .fixed(.medium))
    ]

    /// §3.4 «Сталість».
    public static let steady: [QuestDefinition] = [
        .init(key: "weekly.goalDays", scope: .weekly, slot: .steady, title: .init("Норма ", .count(.days)),
              condition: .daysCount(.goal), difficulty: .byCount(medium: 4, hard: 6)),
        .init(key: "weekly.goalRun", scope: .weekly, slot: .steady,
              title: .init("Норма ", .count(.days), " поспіль"),
              condition: .daysRun(.goal), difficulty: .byCount(medium: 3, hard: 4)),
        .init(key: "weekly.halfDays", scope: .weekly, slot: .steady, title: .init("Половина норми ", .count(.days)),
              condition: .daysCount(.halfGoal), difficulty: .fixed(.easy))
    ]

    /// §3.5 «Звичка» — N з таблиці, але не більше за дні, що лишились, мінус запасний.
    public static let habit: [QuestDefinition] = [
        .init(key: "weekly.weekend", scope: .weekly, slot: .habit, title: .init("Вихідні з нормою"),
              condition: .weekend(.goal), difficulty: .fixed(.medium), baseCount: 2),
        .init(key: "weekly.wakeGlassDays", scope: .weekly, slot: .habit,
              title: .init(.count(.mornings), " зі склянкою"),
              condition: .daysCount(.wakeGlass(withinMinutes: 60)), difficulty: .fixed(.easy), baseCount: 5),
        .init(key: "weekly.halfByDays", scope: .weekly, slot: .habit,
              title: .init(.count(.days), ": половина до обіду"),
              condition: .daysCount(.shareBy(0.5, .curveShare(0.5))), difficulty: .fixed(.medium), baseCount: 4),
        .init(key: "weekly.perfectDays", scope: .weekly, slot: .habit, title: .init(.count(.perfectDays)),
              condition: .daysCount(.allBlocks), difficulty: .fixed(.hard),
              requirements: .init(dayRhythm: true, minLevel: 5), baseCount: 3),
        .init(key: "weekly.goalByDays", scope: .weekly, slot: .habit,
              title: .init(.count(.days), ": норма до вечора"),
              condition: .daysCount(.shareBy(1, .personalGoal)), difficulty: .fixed(.medium), baseCount: 4)
    ]

    /// §3.6 — несподівані (§6). Пікери щоденних їх не бачать: планує `SurprisePicker`, у першу дію дня.
    /// Складність тут — лише вид нагороди: легке — до години (`surpriseShortXp`), середнє — частина доби чи день.
    public static let surprise: [QuestDefinition] = [
        .init(key: "surprise.glassNow", scope: .adhoc, slot: .surprise, title: .init("Склянка зараз"),
              condition: .day(.window(.glass)), difficulty: .fixed(.easy)),
        // Називає частину доби, тож без «Ритму дня» не видається (§0, п. 5). Н1 — ні: «склянка до 14:30» про частини
        // не каже, а прогалину однаково латає.
        .init(key: "surprise.closeBlock", scope: .adhoc, slot: .surprise, title: .init("Закрий ", .block, " до ", .time),
              condition: .day(.blockReached), difficulty: .fixed(.medium), requirements: rhythm),
        .init(key: "surprise.weekday", scope: .adhoc, slot: .surprise, title: .init(.weekday, " з нормою"),
              condition: .day(.shareBy(1, .sleepMinus(minutes: SurpriseRules.latestEndBeforeSleep))),
              difficulty: .fixed(.medium)),
        .init(key: "surprise.flash", scope: .adhoc, slot: .surprise, title: .init("Блискавка: 15 хвилин"),
              condition: .day(.window(.fixed(QuestRules.glassMinMl))), difficulty: .fixed(.easy))
    ]

    /// §3.7 — не видаються, але інстанси поточного дня й тижня на момент оновлення доживають період з тим самим XP.
    public static let retired: [QuestDefinition] = [
        .init(key: "daily.goal", scope: .daily, slot: nil, title: .init("Випити денну норму"),
              condition: .legacy(MetricRule(key: .intakeAdded, period: .day, aggregate: .sum), .dailyGoal),
              difficulty: nil, legacyXp: 25, isRetired: true),
        .init(key: "daily.entries4", scope: .daily, slot: nil, title: .init("Додати 4 записи"),
              condition: .legacy(MetricRule(key: .intakeCount, period: .day, aggregate: .sum), .fixed(4)),
              difficulty: nil, legacyXp: 25, isRetired: true),
        .init(key: "daily.morning", scope: .daily, slot: nil, title: .init("Випити воду зранку"),
              condition: .legacy(MetricRule(key: .partMorning, period: .day, aggregate: .sum), .fixed(200)),
              difficulty: nil, legacyXp: 25, isRetired: true),
        .init(key: "weekly.streak7", scope: .weekly, slot: nil, title: .init("Стрік 7 днів поспіль"),
              condition: .legacy(.currentStreak, .fixed(7)), difficulty: nil, legacyXp: 100, isRetired: true),
        .init(key: "weekly.goal5days", scope: .weekly, slot: nil, title: .init("Випити норму 5 днів"),
              condition: .legacy(MetricRule(key: .dayGoalMet, period: .week, aggregate: .sum), .fixed(5)),
              difficulty: nil, legacyXp: 100, isRetired: true)
    ]

    public static let all: [QuestDefinition] = tempo + rhythmSlot + starter + steady + habit + surprise + retired
    public static let active: [QuestDefinition] = all.filter { !$0.isRetired }

    private static let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    public static func definition(_ key: String) -> QuestDefinition? { byKey[key] }

    static func definitions(_ slot: QuestSlot) -> [QuestDefinition] { active.filter { $0.slot == slot } }
}
