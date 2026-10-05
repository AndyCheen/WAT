import Foundation
import Core
import Persistence

// Вхідні дані планувальника — прості значення без SwiftData й без доменних сервісів:
// планувальник лишається чистою функцією, яку тестують на `FixedClock` (SPEC-NOTIFICATIONS §16.2).

/// Тихий період: дні тижня + від–до (§13.2).
public struct QuietWindow: Sendable, Equatable {
    /// Біт 0 — понеділок … біт 6 — неділя.
    public var weekdayMask: Int
    public var fromMinutes: Int
    public var toMinutes: Int

    public init(weekdayMask: Int = QuietPeriod.allDays, fromMinutes: Int, toMinutes: Int) {
        self.weekdayMask = weekdayMask
        self.fromMinutes = fromMinutes
        self.toMinutes = toMinutes
    }

    /// `index` — 0 для понеділка.
    public func applies(toWeekday index: Int) -> Bool {
        weekdayMask & (1 << index) != 0
    }
}

public enum ReminderCadence: Sendable, Equatable {
    case pace(ReminderFrequency)
    case interval(minutes: Int)
}

/// Налаштування сповіщень одним значенням: профіль (режим дня, склянка, головний вимикач) +
/// `NotificationSettings` + тихі періоди.
public struct NotificationPreferences: Sendable, Equatable {
    public var isEnabled = true
    public var weekday = DaySchedule.weekdayDefault
    /// `nil` — у вихідні той самий розклад.
    public var weekend: DaySchedule?
    public var glassMl = 250
    public var quietWindows: [QuietWindow] = []
    public var remindersEnabled = true
    public var cadence = ReminderCadence.pace(.normal)
    public var followUpEnabled = true
    public var morningEnabled = true
    /// Чекпоінти частин доби (§9, етап B).
    public var checkpointsEnabled = true
    /// Звіти (§11.1): денний — о відбої, тижневий — у вибраний день, місячний — 1-го числа.
    public var dailyReportEnabled = true
    public var weeklyReportEnabled = true
    /// 0 — понеділок … 6 — неділя.
    public var weeklyReportWeekday = 0
    public var weeklyReportMinutes = 10 * 60
    public var monthlyReportEnabled = true
    public var monthlyReportMinutes = 10 * 60
    /// `nil` — о підйомі.
    public var morningMinutes: Int?
    public var eveningEnabled = true
    /// `nil` — за 2 год до відбою.
    public var eveningMinutes: Int?
    public var rescueEnabled = true
    public var echoEnabled = true
    public var comebackEnabled = true
    public var sound = NotificationSound.bubble
    /// «Не сьогодні» — пауза мотиваційних типів до цього моменту (§6.4).
    public var pausedUntil: Date?

    public init() {}

    public static let `default` = NotificationPreferences()

    /// Розклад дня: у суботу й неділю — окремий, якщо його увімкнено.
    public func schedule(isWeekend: Bool) -> DaySchedule {
        isWeekend ? (weekend ?? weekday) : weekday
    }

    public func isPaused(at date: Date) -> Bool {
        pausedUntil.map { date < $0 } ?? false
    }
}

extension NotificationPreferences {
    /// Збирає налаштування з моделей Persistence — єдине місце, де планувальник «бачить» SwiftData.
    @MainActor
    public init(profile: UserProfile, settings: NotificationSettings, quietPeriods: [QuietPeriod]) {
        self.init()
        isEnabled = profile.notificationsEnabled
        weekday = DaySchedule(wakeMinutes: profile.wakeMinutes, sleepMinutes: profile.sleepMinutes)
        weekend = profile.weekendScheduleEnabled
            ? DaySchedule(wakeMinutes: profile.weekendWakeMinutes, sleepMinutes: profile.weekendSleepMinutes)
            : nil
        glassMl = profile.glassMl
        quietWindows = quietPeriods.filter(\.enabled).map {
            QuietWindow(weekdayMask: $0.weekdayMask, fromMinutes: $0.fromMinutes, toMinutes: $0.toMinutes)
        }
        remindersEnabled = settings.remindersEnabled
        checkpointsEnabled = settings.checkpointsEnabled
        dailyReportEnabled = settings.dailyReportEnabled
        weeklyReportEnabled = settings.weeklyReportEnabled
        weeklyReportWeekday = settings.weeklyReportWeekday
        weeklyReportMinutes = settings.weeklyReportMinutes
        monthlyReportEnabled = settings.monthlyReportEnabled
        monthlyReportMinutes = settings.monthlyReportMinutes
        cadence = settings.reminderMode == .pace
            ? .pace(settings.reminderFrequency)
            : .interval(minutes: settings.reminderIntervalMinutes)
        followUpEnabled = settings.followUpEnabled
        morningEnabled = settings.morningEnabled
        morningMinutes = settings.morningCustomMinutes
        eveningEnabled = settings.eveningEnabled
        eveningMinutes = settings.eveningCustomMinutes
        rescueEnabled = settings.rescueEnabled
        echoEnabled = settings.echoEnabled
        comebackEnabled = settings.comebackEnabled
        sound = settings.sound
        pausedUntil = settings.pausedUntil
    }
}

/// Серія на три дні навколо сьогодні. Дзеркало `Gamification.StreakFacts`: пакет сповіщень
/// гейміфікацію не імпортує (§16.10). «Зараховано» — норма або заморозка.
public struct StreakInput: Sendable, Equatable {
    public var countedToday = false
    public var countedYesterday = false
    public var countedDayBefore = false
    public var lengthEndingToday = 0
    public var lengthEndingYesterday = 0
    public var lengthEndingDayBefore = 0

    public init(countedToday: Bool = false, countedYesterday: Bool = false, countedDayBefore: Bool = false,
                lengthEndingToday: Int = 0, lengthEndingYesterday: Int = 0, lengthEndingDayBefore: Int = 0) {
        self.countedToday = countedToday
        self.countedYesterday = countedYesterday
        self.countedDayBefore = countedDayBefore
        self.lengthEndingToday = lengthEndingToday
        self.lengthEndingYesterday = lengthEndingYesterday
        self.lengthEndingDayBefore = lengthEndingDayBefore
    }
}

/// Завдання, на які спираються вставки контексту (§12.2) і ранковий варіант тексту (§14.2).
public struct QuestHints: Sendable, Equatable {
    /// «Випити воду зранку» активне й не виконане.
    public var morningQuestActive = false
    /// Назва щоденного завдання, якому бракує одного запису.
    public var oneEntryLeftTitle: String?
    /// Неділя, і тижневе завдання закривається сьогоднішньою нормою.
    public var weeklyClosesToday: WeeklyHint?

    public struct WeeklyHint: Sendable, Equatable {
        public var title: String
        public var xp: Int
        public init(title: String, xp: Int) {
            self.title = title
            self.xp = xp
        }
    }

    public init(morningQuestActive: Bool = false, oneEntryLeftTitle: String? = nil, weeklyClosesToday: WeeklyHint? = nil) {
        self.morningQuestActive = morningQuestActive
        self.oneEntryLeftTitle = oneEntryLeftTitle
        self.weeklyClosesToday = weeklyClosesToday
    }
}

/// Числа звіту для тексту сповіщення (§11.2). Рахує `Insights`, приносить композиційний корінь:
/// пакет `Notifications` його не імпортує (§16.10).
public struct ReportDigest: Sendable, Equatable {
    public var period: ReportPeriod
    /// За період була хоч одна порція — інакше звіт не надсилається: «ти випив 0 л» — докір (§11.1).
    public var hasIntakes: Bool
    public var totalMl: Int
    /// Норма дня — для денного звіту.
    public var goalMl: Int
    public var goalDays: Int
    public var dayCount: Int
    public var averageMl: Int
    /// Зміна середнього проти попереднього періоду, %.
    public var averageChangePercent: Int?
    /// Найслабша незакрита частина дня — «найслабше — вечір».
    public var weakestPart: String?
    public var longestStreak: Int
    public var glasses: Int

    public init(period: ReportPeriod, hasIntakes: Bool, totalMl: Int = 0, goalMl: Int = 0, goalDays: Int = 0,
                dayCount: Int = 0, averageMl: Int = 0, averageChangePercent: Int? = nil, weakestPart: String? = nil,
                longestStreak: Int = 0, glasses: Int = 0) {
        self.period = period
        self.hasIntakes = hasIntakes
        self.totalMl = totalMl
        self.goalMl = goalMl
        self.goalDays = goalDays
        self.dayCount = dayCount
        self.averageMl = averageMl
        self.averageChangePercent = averageChangePercent
        self.weakestPart = weakestPart
        self.longestStreak = longestStreak
        self.glasses = glasses
    }
}

/// Порція: момент і об'єм.
public struct Portion: Sendable, Equatable {
    public var at: Date
    public var ml: Int

    public init(at: Date, ml: Int) {
        self.at = at
        self.ml = ml
    }
}

/// Усе, що планувальнику треба знати про стан користувача (§16.10). Збирає `AppServices`.
public struct NotificationContext: Sendable, Equatable {
    public var now: Date
    public var timeZone: TimeZone
    /// Норма `G`.
    public var goalMl: Int
    /// Випито сьогодні `A` — зараховане, зі стелею 120 %.
    public var countedMl: Int
    /// Моменти сьогоднішніх порцій.
    public var intakesToday: [Date]
    /// Сьогоднішні порції з об'ємами — для цілей частин доби (§9): `countedMl` один на весь день.
    public var portionsToday: [Portion]
    /// Остання порція взагалі — для дня останньої дії й деградації (§13.5).
    public var lastIntakeAt: Date?
    /// Відкриття застосунку чи дія в ньому (§6.2, «Скидання»).
    public var lastInteractionAt: Date?
    /// Об'єми порцій за 14 днів — для типової порції `P` (§3.3).
    public var portionHistoryMl: [Int]
    /// Хвилина першої порції за останні 14 активних днів — час повернення (§12.1).
    public var firstIntakeMinutes: [Int]
    public var streak: StreakInput
    public var readyFreezes: Int
    public var boostExpiresAt: Date?
    public var lastComebackGiftAt: Date?
    public var lastBounceBackDay: DayKey?
    public var quests: QuestHints
    /// Що дає «Знову в ритмі» (§12.5 Б) — для вставки «+25 XP».
    public var bounceBackXp: Int
    /// XP за ціль частини доби — для тексту чекпоінта (§9).
    public var dayPartXp: Int
    /// Звіти, що можуть потрапити в горизонт (`NotificationPlanner.reportPeriods`).
    public var reports: [ReportDigest]
    public var bounceBackMinStreak: Int
    public var bounceBackCooldownDays: Int
    public var comebackCooldownDays: Int

    public init(
        now: Date, timeZone: TimeZone, goalMl: Int = 2000, countedMl: Int = 0, intakesToday: [Date] = [],
        portionsToday: [Portion] = [],
        lastIntakeAt: Date? = nil, lastInteractionAt: Date? = nil, portionHistoryMl: [Int] = [],
        firstIntakeMinutes: [Int] = [], streak: StreakInput = StreakInput(), readyFreezes: Int = 0,
        boostExpiresAt: Date? = nil, lastComebackGiftAt: Date? = nil, lastBounceBackDay: DayKey? = nil,
        quests: QuestHints = QuestHints(), bounceBackXp: Int = 25, dayPartXp: Int = 10, reports: [ReportDigest] = [],
        bounceBackMinStreak: Int = 3,
        bounceBackCooldownDays: Int = 7, comebackCooldownDays: Int = 30
    ) {
        self.now = now
        self.timeZone = timeZone
        self.goalMl = goalMl
        self.countedMl = countedMl
        self.intakesToday = intakesToday
        self.portionsToday = portionsToday
        self.lastIntakeAt = lastIntakeAt
        self.lastInteractionAt = lastInteractionAt
        self.portionHistoryMl = portionHistoryMl
        self.firstIntakeMinutes = firstIntakeMinutes
        self.streak = streak
        self.readyFreezes = readyFreezes
        self.boostExpiresAt = boostExpiresAt
        self.lastComebackGiftAt = lastComebackGiftAt
        self.lastBounceBackDay = lastBounceBackDay
        self.quests = quests
        self.bounceBackXp = bounceBackXp
        self.dayPartXp = dayPartXp
        self.reports = reports
        self.bounceBackMinStreak = bounceBackMinStreak
        self.bounceBackCooldownDays = bounceBackCooldownDays
        self.comebackCooldownDays = comebackCooldownDays
    }
}

/// Що вже сталося з запланованим раніше — з журналу (§16.8).
public struct JournalEntry: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Ще не настало.
        case pending
        /// Показане (або лежить у Центрі сповіщень).
        case delivered
        /// Настало при відкритому застосунку — не показане (§16.7).
        case suppressed
        case cancelled
    }

    public var identifier: String
    public var type: NotificationType
    public var slot: String
    public var dayKey: DayKey
    public var fireAt: Date
    public var variant: Int
    public var status: Status
    public var response: NotificationResponseKind
    public var respondedAt: Date?

    public init(identifier: String, type: NotificationType, slot: String, dayKey: DayKey, fireAt: Date,
                variant: Int = 0, status: Status = .delivered, response: NotificationResponseKind = .none,
                respondedAt: Date? = nil) {
        self.identifier = identifier
        self.type = type
        self.slot = slot
        self.dayKey = dayKey
        self.fireAt = fireAt
        self.variant = variant
        self.status = status
        self.response = response
        self.respondedAt = respondedAt
    }
}

public struct NotificationJournal: Sendable, Equatable {
    public var entries: [JournalEntry]

    public init(entries: [JournalEntry] = []) {
        self.entries = entries
    }

    public static let empty = NotificationJournal()

    /// Показані сповіщення дня — перешкоди для проміжку 30 хв і частина денного ліміту.
    /// Відлуння не рахується: це реакція на дію (§12.1).
    func shown(on day: DayKey, before date: Date) -> [JournalEntry] {
        entries.filter { $0.dayKey == day && $0.status == .delivered && $0.fireAt <= date && $0.type != .echo }
    }

    /// Останнє «Нагадати за годину».
    var lastSnooze: Date? {
        entries.filter { $0.response == .snooze }.compactMap(\.respondedAt).max()
    }

    /// Остання відповідь на сповіщення — теж дія користувача (§13.5).
    var lastResponse: Date? {
        entries.filter { $0.response != .none }.compactMap(\.respondedAt).max()
    }

    /// Варіанти тексту типу, використані останніми, — новіші спершу.
    func recentVariants(of type: NotificationType, before date: Date) -> [Int] {
        entries
            .filter { $0.type == type && $0.status == .delivered && $0.fireAt <= date }
            .sorted { $0.fireAt > $1.fireAt }
            .map(\.variant)
    }
}
