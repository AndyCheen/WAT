import Foundation
import Core
import Persistence
import Metrics

/// Умова досягнення (SPEC-ACHIEVEMENTS-CATALOG §6). Нове досягнення на наявному правилі — рядок у
/// каталозі; новий вид умови — case тут і обчислення в `DayHistory` чи `AchievementEngine`.
public enum AchievementRule: Sendable {
    /// Лічильник шини метрик чи серія — як у завдань.
    case metric(MetricRule)
    /// `count` подій метрики в межах `withinSeconds` («Дискотека»).
    case burst(MetricKey, count: Int, withinSeconds: Int)
    case level
    /// Факт історії днів.
    case history(HistoryFact)
    /// Факт шляху рівнів і призів.
    case game(GameFact)
    /// Скільки досягнень відкрито.
    case collection(CollectionScope)

    /// Скільки разів сталась подія за весь час.
    static func count(_ key: MetricKey) -> AchievementRule {
        .metric(MetricRule(key: key, period: .all, aggregate: .count))
    }

    static func max(_ key: MetricKey) -> AchievementRule {
        .metric(MetricRule(key: key, period: .all, aggregate: .max))
    }

    var isCollection: Bool {
        if case .collection = self { return true }
        return false
    }

    /// Прогрес рахує мілілітри — підпис показується в системі об'єму людини (WAT-46). Кількість подій
    /// на об'ємній метриці — штуки.
    var measuresVolume: Bool {
        switch self {
        case .history(.countedMl):
            return true
        case .metric(let rule):
            if case .metric(_, _, .count) = rule.source { return false }
            return rule.measuresVolume
        case .burst, .level, .history, .game, .collection:
            return false
        }
    }
}

public enum GameFact: Sendable, Hashable {
    case mysteriesOpened
    case levelChoices
    /// 🌟 «Потрійний XP» випав із таємного призу.
    case tripleFromMystery
}

public enum CollectionScope: Sendable, Hashable {
    /// Будь-які відкриті, зокрема таємні.
    case all
    /// Основний каталог — без таємних і без залежних від функцій (§4.6).
    case core
}

/// Таємні — прапорець, а не категорія: таємним може бути досягнення будь-якого типу (§3).
public enum AchievementSecrecy: Sendable, Equatable {
    case none
    /// 🤫 Сіра плитка «???», у картці — лише підказка, ні умови, ні прогресу (§4.9).
    case hint(String)
    /// 🥚 Пасхалка: до знахідки її немає ні в знімку, ні в лічильнику (§4.10).
    case egg

    public var isEgg: Bool { self == .egg }
}

/// Функція, без якої досягнення не рахується (рішення від 15.10.2026, §4.4). Поки вона вимкнена,
/// досягнення замкнене з підписом замість прогресу; відкрите раніше не забирається.
public enum AchievementGate: Sendable, Equatable {
    case dayRhythm
    case notifications

    public var caption: String {
        switch self {
        case .dayRhythm: return "Увімкни «Ритм дня» в налаштуваннях"
        case .notifications: return "Увімкни сповіщення"
        }
    }
}

/// Стан функцій, від яких залежать досягнення.
public struct AchievementGates: Equatable, Sendable {
    public var dayRhythm: Bool
    public var notifications: Bool

    public init(dayRhythm: Bool = true, notifications: Bool = true) {
        self.dayRhythm = dayRhythm
        self.notifications = notifications
    }

    public static let allOpen = AchievementGates()

    public func isOpen(_ gate: AchievementGate?) -> Bool {
        switch gate {
        case nil: return true
        case .dayRhythm?: return dayRhythm
        case .notifications?: return notifications
        }
    }
}

/// Складність — і орієнтир «коли ≈», і нагорода (SPEC-ACHIEVEMENTS-CATALOG §2).
public enum AchievementDifficulty: Int, Sendable, CaseIterable {
    case easy, medium, hard, legendary

    /// XP за таблицею §2 — чернетка: остаточні числа — WAT-25. Одне місце на весь каталог.
    /// Легкі «Відкриття» дешевші: вони вчать функції, а не вимагають зусиль.
    public func rewardXp(category: AchievementCategory) -> Int {
        switch self {
        case .easy: return category == .discovery ? 15 : 25
        case .medium: return 100
        case .hard: return 300
        case .legendary: return 1000
        }
    }
}

public struct AchievementDefinition: Sendable, Identifiable {
    public let key: String
    public let title: String
    /// Опис на картці. Для пасхалки — «опис після відкриття»: що сталося, без умови (§4.10).
    public let details: String
    public let emoji: String
    public let category: AchievementCategory
    public let difficulty: AchievementDifficulty
    public let rule: AchievementRule
    public let target: Double
    public let secrecy: AchievementSecrecy
    public let gate: AchievementGate?
    /// Опис з об'ємом у системі людини, якщо це не мілілітри: «34 унц. води загалом» (WAT-46).
    public let volumeDetails: (@Sendable (String) -> String)?

    public var id: String { key }
    public var rewardXp: Int { difficulty.rewardXp(category: category) }
    public var isSecret: Bool { secrecy != .none }

    /// Підказка таємного 🤫 — її показує знімок замість умови, поки не відкрито (§4.9).
    public var hint: String? {
        if case .hint(let text) = secrecy { return text }
        return nil
    }

    /// Основний каталог — те, що рахує «Усе зібрано»: таємні на нього не працюють, а залежні від функцій
    /// інакше назавжди закривали б легендарне вимкненим перемикачем (рішення від 15.10.2026).
    public var isCore: Bool { secrecy == .none && gate == nil }

    public init(
        key: String,
        title: String,
        details: String,
        volumeDetails: (@Sendable (String) -> String)? = nil,
        emoji: String,
        category: AchievementCategory,
        difficulty: AchievementDifficulty,
        rule: AchievementRule,
        target: Double = 1,
        secrecy: AchievementSecrecy = .none,
        gate: AchievementGate? = nil
    ) {
        self.key = key
        self.title = title
        self.details = details
        self.volumeDetails = volumeDetails
        self.emoji = emoji
        self.category = category
        self.difficulty = difficulty
        self.rule = rule
        self.target = target
        self.secrecy = secrecy
        self.gate = gate
    }
}

/// Усе, з чого рахуються правила досягнень за один прохід.
@MainActor
struct AchievementInputs {
    let rules: RuleContext
    let history: DayHistory
    let level: Int
    let game: [GameFact: Double]
    let burst: (MetricKey, Int, Int) -> Double
    let gates: AchievementGates
}
