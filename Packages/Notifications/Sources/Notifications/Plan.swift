import Foundation
import Core
import Persistence

/// Куди веде тап по сповіщенню (§16.4). Розбирає його `Features` — тут лише намір.
public enum NotificationTapRoute: Sendable, Equatable {
    case home
    /// Шторка «Інше» з типовою порцією `P` — «екран вибору об'єму» з чорновика (§6.4).
    case customAmount(ml: Int)
    /// Картка призу «Заморозка серії» — заморозка робиться лише з неї (§12.1).
    case freezeCard
    /// Картка призу ⚡ — подарунок за повернення.
    case boostCard
    case achievement(key: String)
    case progress
    /// Вікно «Склянка» — лише з ранкової склянки (§7, §16.4).
    case glass
    /// Звіт-історія; кілька періодів — злите «Підсумки тижня й місяця» грає їх підряд (§11.1).
    case report([ReportPeriod])

    /// Рядок для `userInfo` — запит переживає перезапуск процесу.
    public var encoded: String {
        switch self {
        case .home: return "home"
        case .customAmount(let ml): return "custom:\(ml)"
        case .freezeCard: return "freeze"
        case .boostCard: return "boost"
        case .achievement(let key): return "achievement:\(key)"
        case .progress: return "progress"
        case .glass: return "glass"
        case .report(let periods): return "report:" + periods.map(\.encoded).joined(separator: ",")
        }
    }

    public init(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "custom": self = .customAmount(ml: Int(parts.last ?? "") ?? 250)
        case "freeze": self = .freezeCard
        case "boost": self = .boostCard
        case "achievement" where parts.count == 2: self = .achievement(key: parts[1])
        case "progress": self = .progress
        case "glass": self = .glass
        case "report" where parts.count == 2:
            let periods = parts[1].split(separator: ",").compactMap { ReportPeriod(encoded: String($0)) }
            self = periods.isEmpty ? .home : .report(periods)
        default: self = .home
        }
    }
}

/// Пріоритет при зіткненні двох сповіщень ближче ніж за 30 хв (§13.3). Менше — сильніше.
public enum NotificationPriority: Int, Comparable, Sendable {
    case rescue = 1
    case evening = 2
    /// Ранкова склянка; повернення замінює її, тож має той самий пріоритет.
    case morning = 3
    case challenge = 4
    case checkpoint = 5
    case reminderPrimary = 6
    case reminderFollowUp = 7
    /// Звіти за увагу не змагаються, але зсуваються, щоб між ними й активним було ≥ 30 хв (§13.3).
    case report = 8

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Набір дій у сповіщенні (§16.4). Дії прив'язані до категорії, а не до запиту, тож
/// усі типи з єдиною дією «+склянка» ділять одну категорію.
public enum NotificationCategory: String, Sendable, CaseIterable {
    /// «+склянка», «Інший об'єм», «Нагадати за годину», «Не сьогодні».
    case reminder = "REMINDER"
    /// Лише «+склянка» — ранкова склянка, «можна закрити», ранковий порятунок, повернення.
    case glass = "GLASS"
}

/// Наскільки сповіщення перериває (§11.1): тихий звіт за день — `.passive`, без звуку й без
/// засвічення екрана, лише в Центрі сповіщень. `timeSensitive` не використовується ніде (§13.2).
public enum NotificationInterruption: String, Sendable, Equatable {
    case active
    case passive
}

/// Ідентифікатори дій — однакові в запиті й у відповіді.
public enum NotificationActionID {
    public static let addGlass = "wt.add"
    public static let otherAmount = "wt.other"
    public static let snooze = "wt.snooze"
    public static let pause = "wt.pause"
}

/// Одне сповіщення плану — уже з текстом і часом.
public struct PlannedNotification: Sendable, Equatable, Identifiable {
    /// `wt.<тип>.<dayKey>.<слот>` — детермінований, щоб перепланування знімало зайве й
    /// додавало нове без дублікатів (§16.2).
    public var id: String
    public var type: NotificationType
    /// Ситуація всередині типу: `primary`, `followUp`, `closable`, `soothing`, `am`, `pm`, `1`, `2`…
    public var slot: String
    public var dayKey: DayKey
    public var fireAt: Date
    /// «Плаваючий» час іде за поясом пристрою: ранкова склянка о 08:00 буде о 08:00 і в
    /// Лісабоні. Нагадування — абсолютні моменти від останньої порції (§16.2).
    public var isFloating: Bool
    public var priority: NotificationPriority
    public var category: NotificationCategory?
    public var title: String
    public var body: String
    public var variant: Int
    public var tapRoute: NotificationTapRoute
    public var interruption: NotificationInterruption
    /// Без звуку незалежно від вибору в налаштуваннях — звіти (§11.1).
    public var isSilent: Bool

    public init(id: String, type: NotificationType, slot: String, dayKey: DayKey, fireAt: Date,
                isFloating: Bool, priority: NotificationPriority, category: NotificationCategory?,
                title: String = "", body: String = "", variant: Int = 0, tapRoute: NotificationTapRoute,
                interruption: NotificationInterruption = .active, isSilent: Bool = false) {
        self.id = id
        self.type = type
        self.slot = slot
        self.dayKey = dayKey
        self.fireAt = fireAt
        self.isFloating = isFloating
        self.priority = priority
        self.category = category
        self.title = title
        self.body = body
        self.variant = variant
        self.tapRoute = tapRoute
        self.interruption = interruption
        self.isSilent = isSilent
    }

    public static func identifier(_ type: NotificationType, day: DayKey, slot: String) -> String {
        "wt.\(type.key).\(day.rawValue).\(slot)"
    }

    /// Тип за ідентифікатором — для відповіді, що прийшла без журналу (холодний старт).
    public static func type(ofIdentifier identifier: String) -> NotificationType? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2, parts[0] == "wt" else { return nil }
        return NotificationType(key: String(parts[1]))
    }
}

/// Результат планування: що запланувати + службове для DEBUG-екрана «План сповіщень».
public struct NotificationPlan: Sendable, Equatable {
    public var items: [PlannedNotification]
    public var generatedAt: Date
    /// Типова порція `P`, з якої рахувались тексти й шторка «Інше».
    public var typicalPortionMl: Int
    /// День останньої дії — від нього рахується деградація (§13.5).
    public var lastActionDay: DayKey?
    public var glassMl: Int

    public init(items: [PlannedNotification], generatedAt: Date, typicalPortionMl: Int,
                lastActionDay: DayKey?, glassMl: Int) {
        self.items = items
        self.generatedAt = generatedAt
        self.typicalPortionMl = typicalPortionMl
        self.lastActionDay = lastActionDay
        self.glassMl = glassMl
    }

    public static let empty = NotificationPlan(
        items: [], generatedAt: .distantPast, typicalPortionMl: 250, lastActionDay: nil, glassMl: 250
    )
}
