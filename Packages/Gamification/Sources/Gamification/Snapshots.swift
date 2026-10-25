import Foundation
import Core
import Persistence

/// Незмінні знімки для UI — екрани не працюють з `@Model` напряму.

public struct StreakSummary: Equatable, Sendable {
    public let current: Int
    public let longest: Int
    public let freezeTokens: Int
    public let lastCountedDay: DayKey?

    /// - Parameter freezeTokens: кількість готових заморозок в інвентарі.
    public init(current: Int, longest: Int, freezeTokens: Int = 0, lastCountedDay: DayKey?) {
        self.current = current
        self.longest = longest
        self.freezeTokens = freezeTokens
        self.lastCountedDay = lastCountedDay
    }

    public static let empty = StreakSummary(current: 0, longest: 0, freezeTokens: 0, lastCountedDay: nil)
}

/// Завдання для UI. Тексти тут не складаються: назву (час, одиниці, плюраль) і підпис прогресу будує
/// `QuestPresenter` у `Features` з шаблону `title` і параметрів інстансу.
public struct QuestSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let scope: QuestScope
    /// `nil` — архівне (SPEC-QUESTS §3.7).
    public let slot: QuestSlot?
    public let title: QuestTitle
    public let kind: QuestKind
    /// Мілілітри для `.volume`, штуки для `.count`, дні для `.days`.
    public let progress: Double
    public let target: Double
    public let isDone: Bool
    public let difficulty: QuestDifficulty?
    /// XP з інстансу — те, що буде нараховано (буст і загальний множник — зверху).
    public let rewardXp: Int
    /// Мить, після якої невиконане тихо зникає (§7).
    public let deadline: Date?
    /// T у назві («Половина до 14:00»).
    public let deadlineMinute: Int?
    /// N у назві («Норма 5 днів»).
    public let count: Int?
    /// Блок Д7 і скільки блоків у дні — щоб назвати його «ранок / день / вечір».
    public let blockIndex: Int?
    public let blockCount: Int?
    /// Несподіване: мить появи — до неї його не видно ніде (§6.4).
    public let visibleFrom: Date?
    /// Н3 — день тижня в назві, 0 — понеділок.
    public let weekdayIndex: Int?
    /// Особиста ціль «Закрий блок» (WAT-67): назва тоді — «Вдень — 500 мл», а не «Закрий день».
    public let targetMl: Int?

    public init(
        id: UUID, key: String, scope: QuestScope, slot: QuestSlot?, title: QuestTitle, kind: QuestKind,
        progress: Double, target: Double, isDone: Bool, difficulty: QuestDifficulty?, rewardXp: Int,
        deadline: Date? = nil, deadlineMinute: Int? = nil, count: Int? = nil, blockIndex: Int? = nil,
        blockCount: Int? = nil, visibleFrom: Date? = nil, weekdayIndex: Int? = nil, targetMl: Int? = nil
    ) {
        self.id = id
        self.key = key
        self.scope = scope
        self.slot = slot
        self.title = title
        self.kind = kind
        self.progress = progress
        self.target = target
        self.isDone = isDone
        self.difficulty = difficulty
        self.rewardXp = rewardXp
        self.deadline = deadline
        self.deadlineMinute = deadlineMinute
        self.count = count
        self.blockIndex = blockIndex
        self.blockCount = blockCount
        self.visibleFrom = visibleFrom
        self.weekdayIndex = weekdayIndex
        self.targetMl = targetMl
    }

    public var fraction: Double { target > 0 ? min(1, progress / target) : 0 }

    /// Чи видно завдання в цю мить: несподіване — з хвилини появи; невиконане — до свого дедлайну. Одне правило для
    /// головного, віджета й сповіщень.
    public func isVisible(at date: Date) -> Bool {
        (visibleFrom.map { $0 <= date } ?? true) && (isDone || (deadline.map { $0 > date } ?? true))
    }

    /// «Блискавка» — свій вид на картці, решта — «Несподіване» (§9.1).
    public var isFlash: Bool { key == "surprise.flash" }
}

/// Усі завдання головного (SPEC-QUESTS §9.1): щоденні й тижневі без прострочених невиконаних.
public struct QuestBoard: Equatable, Sendable {
    public var daily: [QuestSnapshot]
    public var weekly: [QuestSnapshot]
    /// Пт–Нд без тижневих: «Тижневі завдання — з понеділка».
    public var weeklyStartsMonday: Bool
    /// Днів до кінця тижня разом із сьогоднішнім — «ЦЬОГО ТИЖНЯ · ЩЕ 5 ДН.».
    public var weekDaysLeft: Int
    /// Щоденні, що зникли за дедлайном невиконаними. Їх у `daily` немає, але без них «Усе на сьогодні 🎉»
    /// показалося б і тоді, коли виконано лише одне з двох (§9.1: тоді секції «Сьогодні» немає зовсім).
    public var expiredDaily: Int
    /// Несподіване сьогодні — активне (і ще не видиме: `visibleFrom` у майбутньому) чи виконане. Прострочене й
    /// скасоване сюди не потрапляють.
    public var surprise: QuestSnapshot?

    public init(daily: [QuestSnapshot] = [], weekly: [QuestSnapshot] = [], weeklyStartsMonday: Bool = false,
                weekDaysLeft: Int = 7, expiredDaily: Int = 0, surprise: QuestSnapshot? = nil) {
        self.daily = daily
        self.weekly = weekly
        self.weeklyStartsMonday = weeklyStartsMonday
        self.weekDaysLeft = weekDaysLeft
        self.expiredDaily = expiredDaily
        self.surprise = surprise
    }

    public static let empty = QuestBoard()
}

/// Розріз списку квестів на активні й виконані.
///
/// Живе тут, а не в екранах: правило «виконане» одне для блоку головного, віджета й тестів, а однакові
/// `filter` розʼїжджаються при першій же зміні правила.
extension Collection where Element == QuestSnapshot {
    /// Ще не виконані — те, що показуємо за замовчуванням.
    public var active: [QuestSnapshot] { filter { !$0.isDone } }
    public var completed: [QuestSnapshot] { filter(\.isDone) }
}

/// Стан досягнення з погляду UI. Рахується в знімку, а не в екранах —
/// інакше три поверхні модуля (блок 3f, екран 2e, картка) розійдуться в правилі.
public enum AchievementState: Equatable, Sendable {
    /// Користувач іще не наближався: `value == 0`.
    case locked
    case inProgress
    case unlocked
}

/// Знімок досягнення для UI. `title`, `details` і `emoji` — уже те, що можна показати: у закритого
/// таємного це «???», підказка й 🤫, справжніх значень знімок не несе зовсім (SPEC-ACHIEVEMENTS §6).
public struct AchievementSnapshot: Equatable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public internal(set) var details: String
    public let emoji: String
    public let category: AchievementCategory
    public let value: Double
    public let target: Double
    /// Штуки чи мілілітри — від правила в каталозі (WAT-52).
    public let unit: AchievementUnit
    public let isUnlocked: Bool
    public let isSecret: Bool
    public let rewardXp: Int
    public let unlockedAt: Date?
    /// Відкрите, але ще не переглянуте — помаранчева крапка на бейджі й плитці.
    public let isNew: Bool
    /// 🤫 Таємне ще не відкрите: сіра плитка «???», у картці — лише підказка (§4.9).
    public let isMasked: Bool
    /// 🥚 Знайдена пасхалка. Незнайдених у знімку немає (§4.10).
    public let isEgg: Bool
    /// Зняте з каталогу (WAT-60) і відкрите раніше: звичайна плитка, але поза «Відкрито N / M» (§10.2).
    /// Невідкритих знятих у знімку немає.
    public let isRetired: Bool
    /// «Увімкни сповіщення» — функцію вимкнено, і досягнення не рахується (§4.4). Замість прогресу.
    public let lockedCaption: String?
    /// Додатковий рядок картки — «Пасхалка! Тут їх більше» у першої знайденої.
    public let note: String?
    /// Досягнення про об'єм у людини, що рахує в унціях (WAT-46).
    public var ounces: VolumeUnit?

    public var id: String { key }

    public static let maskedTitle = "???"
    public static let maskedEmoji = "🤫"

    public init(
        key: String, title: String, details: String, emoji: String,
        category: AchievementCategory, value: Double, target: Double, unit: AchievementUnit = .count,
        isUnlocked: Bool, isSecret: Bool,
        rewardXp: Int = 0, unlockedAt: Date? = nil, isNew: Bool = false,
        isMasked: Bool = false, isEgg: Bool = false, isRetired: Bool = false,
        lockedCaption: String? = nil, note: String? = nil
    ) {
        self.key = key
        self.title = title
        self.details = details
        self.emoji = emoji
        self.category = category
        self.value = value
        self.target = target
        self.unit = unit
        self.isUnlocked = isUnlocked
        self.isSecret = isSecret
        self.rewardXp = rewardXp
        self.unlockedAt = unlockedAt
        self.isNew = isNew
        self.isMasked = isMasked
        self.isEgg = isEgg
        self.isRetired = isRetired
        self.lockedCaption = lockedCaption
        self.note = note
    }

    public var fraction: Double { target > 0 ? min(1, value / target) : 0 }

    public var state: AchievementState {
        if isUnlocked { return .unlocked }
        return fraction > 0 ? .inProgress : .locked
    }

    /// Ціль в одну дію: «Відкриття», календарні, більшість таємних (WAT-51). Прогресу в них немає —
    /// досягнення або є, або ні, тож смуга й «0/1» нічого не міряють.
    public var isOneStep: Bool { target <= 1 }

    /// Чи показувати прогрес: не в відкритого, не в таємного, не в разового й не там, де замість нього підпис.
    public var showsProgress: Bool { !isUnlocked && !isMasked && !isOneStep && lockedCaption == nil }

    /// «5/7», «950/1000», «3.4/10» — компактний підпис під смугою плитки; одиниця — `unitLabel`.
    public var progressLabel: String {
        if isUnlocked { return "Готово" }
        let shown = shownNumbers
        return "\(shown.value)/\(shown.target)"
    }

    /// «5 / 7», «3.4 / 10» — у картці деталей, де під числом є місце дихати.
    public var valueLabel: String {
        let shown = shownNumbers
        return "\(shown.value) / \(shown.target)"
    }

    /// «мл» / «л» / «унц.» після чисел, у штук — `nil`. Окремо від чисел: у картці вони — Fredoka, а в неї
    /// немає кирилиці (`WTFont`), тож одиниця йде своїм шрифтом.
    public var unitLabel: String? {
        switch unit {
        case .count: return nil
        case .milliliters:
            if ounces != nil { return VolumeUnit.ounceSymbol }
            return inLiters ? "л" : "мл"
        }
    }

    /// «5 із 7», «3,4 із 10 літрів» — для VoiceOver: «5/7» він читає як «5 слеш 7», а «л» — літерою.
    public var spokenProgress: String {
        let shown = shownNumbers
        let numbers = "\(shown.value) із \(shown.target)".replacingOccurrences(of: ".", with: ",")
        guard unit == .milliliters else { return numbers }
        // Слово узгоджується з ціллю — останнім числом фрази: «із 10 літрів», «із 2,5 літра».
        let word: String
        if let ounces {
            word = Plural.uk(ounces.units(Int(target)), one: "унція", few: "унції", many: "унцій")
        } else if inLiters, (target / 1000).rounded() != target / 1000 {
            word = "літра"
        } else if inLiters {
            word = Plural.uk(Int(target / 1000), one: "літр", few: "літри", many: "літрів")
        } else {
            word = Plural.uk(Int(target), one: "мілілітр", few: "мілілітри", many: "мілілітрів")
        }
        return "\(numbers) \(word)"
    }

    // MARK: Об'єм (WAT-46, WAT-52)

    /// Як на кнопках порцій: ціль до 1 л — мілілітри, більша — літри. Одиниця одна на весь підпис:
    /// поки досягнення закрите, значення менше за ціль, тож «950/1000 мл» не мішає мл і л.
    /// В унціях — цілі унції без переходу на більшу одиницю, як скрізь у застосунку.
    private var inLiters: Bool { unit == .milliliters && ounces == nil && target > 1000 }

    /// Значення й ціль в одиницях показу — одне округлення на плитку, картку й VoiceOver. Літри — вниз
    /// до 0.1 л, від 10 л — до цілих: у закритого «9.9/10 л», а не «10/10 л», і без «123.4/250 л»,
    /// де десяті — шум. Крапка, як на кнопках порцій і кільці («1.05 л»), а не кома зі сповіщень.
    private var shownNumbers: (value: String, target: String) {
        let shown = Int(min(value, target))
        if let ounces { return ("\(ounces.units(shown))", "\(ounces.units(Int(target)))") }
        guard inLiters else { return ("\(shown)", "\(Int(target))") }
        let liters = shown < 10_000 ? Double(shown / 100) / 10 : Double(shown / 1000)
        return (Self.number(liters), Self.number(target / 1000))
    }

    /// «3.4», «10», «2.5» — без хвостових нулів.
    private static func number(_ value: Double) -> String { String(format: "%g", value) }
}

/// Лічильник екрана 2e: «Відкрито N / M» — лише видимий каталог, а знайдені пасхалки окремо, «🥚 N»,
/// без загального числа — скільки їх усього, теж секрет (§4.10).
public struct AchievementTally: Equatable, Sendable {
    public let unlocked: Int
    public let total: Int
    public let eggs: Int
}

/// Зріз за станом — чипи на екрані 2e (SPEC-ACHIEVEMENTS §3.2).
public enum AchievementStateFilter: String, CaseIterable, Sendable {
    case all, inProgress, unlocked, locked

    public var title: String {
        switch self {
        case .all: return "Усі"
        case .inProgress: return "У процесі"
        case .unlocked: return "Відкриті"
        case .locked: return "Закриті"
        }
    }

    public func matches(_ item: AchievementSnapshot) -> Bool {
        switch self {
        case .all: return true
        case .inProgress: return item.state == .inProgress
        case .unlocked: return item.isUnlocked
        // «Закриті» — усе невідкрите, зокрема й те, що в процесі: чип відповідає
        // на «чого в мене ще немає», а не повторює «У процесі».
        case .locked: return !item.isUnlocked
        }
    }
}

/// Єдиний порядок досягнень для екрана 2e і блоку 3f (SPEC-ACHIEVEMENTS §3.4).
///
/// Екран має відповідати на «що я можу взяти наступним», а не бути вітриною минулого:
/// щойно відкриті → найближчі до розблокування → решта відкритих → не розпочаті → закриті таємні.
extension Collection where Element == AchievementSnapshot {
    public var sortedForDisplay: [AchievementSnapshot] {
        func group(_ item: AchievementSnapshot) -> Int {
            if item.isNew { return 0 }
            if item.isMasked { return 4 }
            switch item.state {
            case .inProgress: return 1
            case .unlocked: return 2
            case .locked: return 3
            }
        }
        return enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (lhs.element, rhs.element)
                let (gl, gr) = (group(l), group(r))
                if gl != gr { return gl < gr }
                switch gl {
                case 0, 2:
                    let (dl, dr) = (l.unlockedAt ?? .distantPast, r.unlockedAt ?? .distantPast)
                    if dl != dr { return dl > dr }
                case 1:
                    if l.fraction != r.fraction { return l.fraction > r.fraction }
                default:
                    break
                }
                // Рівні ключі сортування лишаються в порядку каталогу — сітка не «тасується».
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public var tally: AchievementTally {
        let visible = filter { !$0.isEgg && !$0.isRetired }
        return AchievementTally(
            unlocked: visible.filter(\.isUnlocked).count, total: visible.count, eggs: filter(\.isEgg).count
        )
    }

    /// Вітрина блоку 3f: лише відкриті й ті, що в процесі, не більше двох рядів по 4.
    /// Нульовий прогрес не показуємо ніколи — на 3f немає місця пояснювати сірий кружечок.
    public var showcase: [AchievementSnapshot] {
        Array(sortedForDisplay.filter { $0.state != .locked }.prefix(AchievementCatalog.showcaseLimit))
    }
}

/// Стан призу з погляду UI (SPEC-PRIZES §9.3). Прострочення буста — **похідне** від
/// `clock.now`, без фонових задач: після 00:00 знімок сам каже `.expired`.
public enum PrizeState: Equatable, Sendable {
    case ready, active, used, expired
}

public struct RewardSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let title: String
    public let details: String
    public let emoji: String
    public let kind: RewardKind
    public let state: PrizeState
    /// Готовий і ще не переглянутий — помаранчева крапка на іконці.
    public let isNew: Bool
    public let acquiredAt: Date
    public let activatedAt: Date?
    public let expiresAt: Date?

    public init(
        id: UUID, key: String, title: String, details: String,
        emoji: String, kind: RewardKind, state: PrizeState, isNew: Bool = false,
        acquiredAt: Date, activatedAt: Date? = nil, expiresAt: Date? = nil
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.details = details
        self.emoji = emoji
        self.kind = kind
        self.state = state
        self.isNew = isNew
        self.acquiredAt = acquiredAt
        self.activatedAt = activatedAt
        self.expiresAt = expiresAt
    }

    /// Для бустів — у скільки разів множиться XP (⚡ 2, 🌟 3); для решти `nil`.
    public var boostFactor: Int? { RewardCatalog.definition(key)?.boostFactor }

    /// Скільки лишилось дії буста; 0 — вже не діє.
    public func remaining(at date: Date) -> TimeInterval {
        guard let expiresAt else { return 0 }
        return max(0, expiresAt.timeIntervalSince(date))
    }

    /// Частка часу, що лишилась, — смуга на hero-картці спадає від 1 до 0.
    public func remainingFraction(at date: Date) -> Double {
        guard let activatedAt, let expiresAt, expiresAt > activatedAt else { return 0 }
        return min(1, remaining(at: date) / expiresAt.timeIntervalSince(activatedAt))
    }
}

/// Який день заморозить заморозка, використана зараз (SPEC-PRIZES §6.2,
/// правило — у `StreakEngine.freezeTarget(at:)`).
public enum FreezeTarget: Equatable, Sendable {
    /// Учора пропущено, а позавчора закінчується серія — її й рятуємо.
    case yesterday(savedStreak: Int)
    case today
    /// Сьогодні вже зараховано — заморожувати нічого, кнопка неактивна.
    case todayAlreadyCounted
}

/// Однакові готові призи — один рядок з лічильником, а не N карток (§4.1).
public struct PrizeStack: Equatable, Identifiable, Sendable {
    public let key: String
    public let count: Int
    public let isNew: Bool
    /// Використовується найстаріший предмет стосу (FIFO).
    public let oldest: RewardSnapshot
    /// Лише для заморозки.
    public let freezeTarget: FreezeTarget?

    public var id: String { key }

    public init(key: String, count: Int, isNew: Bool, oldest: RewardSnapshot, freezeTarget: FreezeTarget?) {
        self.key = key
        self.count = count
        self.isNew = isNew
        self.oldest = oldest
        self.freezeTarget = freezeTarget
    }
}

/// Інвентар для блоку 3f і екрана «Призи» — один розріз на обидві поверхні,
/// інакше вони розійдуться в правилі (урок модуля досягнень).
public struct PrizeInventory: Equatable, Sendable {
    /// Діючі бусти — статус у заголовку 3f і hero-картки на екрані «Призи».
    public let active: [RewardSnapshot]
    /// Готові стоси в порядку каталогу: 🧊 → 🌟 → ⚡.
    public let ready: [PrizeStack]

    public init(active: [RewardSnapshot], ready: [PrizeStack]) {
        self.active = active
        self.ready = ready
    }

    public static let empty = PrizeInventory(active: [], ready: [])

    public var isEmpty: Bool { active.isEmpty && ready.isEmpty }
}

extension Collection where Element == RewardSnapshot {
    /// Лише `.active` і `.ready`: використане й прострочене з інтерфейсу зникає (§3.1).
    public func inventory(freezeTarget: FreezeTarget?) -> PrizeInventory {
        let active = filter { $0.state == .active }.sorted { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
        let ready = filter { $0.state == .ready }
        let stacks: [PrizeStack] = RewardCatalog.all.compactMap { definition in
            let items = ready.filter { $0.key == definition.key }.sorted { $0.acquiredAt < $1.acquiredAt }
            guard let oldest = items.first else { return nil }
            return PrizeStack(
                key: definition.key, count: items.count, isNew: items.contains(where: \.isNew),
                oldest: oldest,
                freezeTarget: definition.key == RewardCatalog.freezeKey ? freezeTarget : nil
            )
        }
        return PrizeInventory(active: active, ready: stacks)
    }
}

/// Що відкрила остання дія користувача — черга `GamificationService.takeRecentUnlocks()`.
///
/// Не лише досягнення: подарунок за повернення й «Знову в ритмі» теж показуються тостом
/// у момент дії (SPEC-NOTIFICATIONS §12.5), а `HydrationService` про гейміфікацію не знає.
public struct RecentUnlocks: Equatable, Sendable {
    public var achievements: [AchievementSnapshot]
    /// ⚡ «Подвійний XP» за першу порцію після перерви.
    public var comebackGift: RewardSnapshot?
    /// Скільки XP дав «Знову в ритмі» (з бустом, якщо діяв).
    public var bounceBackXp: Int?

    public init(achievements: [AchievementSnapshot] = [], comebackGift: RewardSnapshot? = nil, bounceBackXp: Int? = nil) {
        self.achievements = achievements
        self.comebackGift = comebackGift
        self.bounceBackXp = bounceBackXp
    }

    public var isEmpty: Bool { achievements.isEmpty && comebackGift == nil && bounceBackXp == nil }

    public static let empty = RecentUnlocks()
}

/// Серія на три дні навколо сьогодні — вхід для сповіщень: порятунок серії й «Знову в ритмі»
/// (SPEC-NOTIFICATIONS §8, §12.1, §12.5). «Зараховано» — норма або заморозка, як у `freezeTarget`.
public struct StreakFacts: Equatable, Sendable {
    public let countedToday: Bool
    public let countedYesterday: Bool
    public let countedDayBefore: Bool
    /// Дні з нормою в ланцюгу, що закінчується на цей день; 0, якщо день не зараховано.
    public let lengthEndingToday: Int
    public let lengthEndingYesterday: Int
    public let lengthEndingDayBefore: Int

    public init(countedToday: Bool, countedYesterday: Bool, countedDayBefore: Bool,
                lengthEndingToday: Int, lengthEndingYesterday: Int, lengthEndingDayBefore: Int) {
        self.countedToday = countedToday
        self.countedYesterday = countedYesterday
        self.countedDayBefore = countedDayBefore
        self.lengthEndingToday = lengthEndingToday
        self.lengthEndingYesterday = lengthEndingYesterday
        self.lengthEndingDayBefore = lengthEndingDayBefore
    }
}
