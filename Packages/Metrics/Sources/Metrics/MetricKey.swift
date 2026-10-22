import Foundation

/// Реєстр метрик — єдине джерело правди для завдань, досягнень і графіків (PLAN.md §4).
///
/// Нова механіка не додає код у чужі модулі: вона або публікує нову метрику,
/// або описує правило поверх наявної.
public struct MetricKey: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    // Вода
    public static let intakeAdded: MetricKey = "intake.added"
    public static let intakeCount: MetricKey = "intake.count"
    public static let intakeRemoved: MetricKey = "intake.removed"
    public static let intakeRestored: MetricKey = "intake.restored"
    public static let dayTotal: MetricKey = "day.total"
    public static let dayGoalMet: MetricKey = "day.goalMet"
    public static let dayCompletionPct: MetricKey = "day.completionPct"

    // Частини доби
    public static let partMorning: MetricKey = "part.morning"
    public static let partNoon: MetricKey = "part.noon"
    public static let partAfternoon: MetricKey = "part.afternoon"
    public static let partEvening: MetricKey = "part.evening"
    public static let partNight: MetricKey = "part.night"

    // Гейміфікація
    public static let streakCurrent: MetricKey = "streak.current"
    public static let xpEarned: MetricKey = "xp.earned"
    public static let levelReached: MetricKey = "level.reached"
    public static let questCompleted: MetricKey = "quest.completed"
    public static let achievementUnlocked: MetricKey = "achievement.unlocked"
    public static let prizeActivated: MetricKey = "prize.activated"

    // Поведінка
    public static let appOpened: MetricKey = "app.opened"
    /// Порція протягом 60 хв після сповіщення; значення — хвилини до порції (SPEC-NOTIFICATIONS §3.2).
    public static let reminderResponded: MetricKey = "reminder.responded"

    // Сповіщення (SPEC-NOTIFICATIONS §16.9). `sourceRef` — id рядка журналу, тож повторна
    // звірка при переплануванні нічого не подвоює.
    public static let notificationDelivered: MetricKey = "notification.delivered"
    public static let notificationOpened: MetricKey = "notification.opened"
    public static let notificationSnoozed: MetricKey = "notification.snoozed"
    public static let notificationPaused: MetricKey = "notification.paused"
    /// Дозвіл на сповіщення є — один раз на установку (досягнення «На звʼязку», знято в WAT-60).
    public static let notificationAuthorized: MetricKey = "notification.authorized"
    /// Порція за 15 хв після нагадування (досягнення «Чуйність»). `sourceRef` — рядок журналу, як у
    /// `reminder.responded`: одна відповідь — одна подія.
    public static let reminderQuick: MetricKey = "reminder.quick"
    /// Норма закрита після вечірнього «порятунку серії» (досягнення «Вчасно»). `sourceRef` — той самий,
    /// що в `day.goalMet`: відкотили норму — відкотилось і це.
    public static let streakRescued: MetricKey = "streak.rescued"
    /// Норма закрита без жодного доставленого нагадування, коли нагадування ввімкнені («На крок
    /// попереду»). `sourceRef` — як у `day.goalMet`.
    public static let dayGoalAhead: MetricKey = "day.goalAhead"

    // Гра (SPEC-ACHIEVEMENTS-CATALOG §4.6)
    /// Виконано всі щоденні завдання дня. `sourceRef` — детермінований від дня: завдання знову
    /// відкрилось — подію відкочує `GamificationService`.
    public static let questsAllDaily: MetricKey = "quest.allDaily"
    /// Виконано тижневе завдання («Тижнева мета», WAT-60). Пишеться поруч із `quest.completed` з тим самим
    /// `sourceRef` — завданням, тож відкочується разом із ним.
    public static let weeklyQuestCompleted: MetricKey = "quest.weeklyCompleted"

    // Відкриття функцій і пасхалки (SPEC-ACHIEVEMENTS-CATALOG §4.7, §4.10). Разові дії мають
    // детермінований `sourceRef` — повтор ідемпотентністю шини нічого не додає.
    /// Порція власного об'єму через «Інше». `sourceRef` — порція: її скасували — подія теж зникла.
    public static let customPortion: MetricKey = "portion.custom"
    public static let presetsChanged: MetricKey = "presets.changed"
    public static let scheduleEdited: MetricKey = "schedule.edited"
    public static let scheduleOfferAccepted: MetricKey = "schedule.offerAccepted"
    public static let weekReportFinished: MetricKey = "report.weekFinished"
    public static let monthReportFinished: MetricKey = "report.monthFinished"
    public static let pastDayOpened: MetricKey = "history.pastDayOpened"
    public static let darkTheme: MetricKey = "theme.dark"
    /// Кожна зміна теми — без `sourceRef`: «Дискотека» рахує зміни за хвилину.
    public static let themeChanged: MetricKey = "theme.changed"
    /// Екран відкрито — `sourceRef` від назви екрана, тож лічильник = кількість різних екранів.
    public static let screenOpened: MetricKey = "screen.opened"
    public static let xpGuideOpened: MetricKey = "guide.xpOpened"

    // Розділ «Знання» (SPEC-LEARN §7). `sourceRef` — детермінований від історії: перечитана історія
    // лічильник не збільшує, тож лічильник = кількість різних дочитаних історій.
    public static let learnCompleted: MetricKey = "learn.completed"
    /// Дочитано історію полиці «Вода й тіло» — «Знавець води».
    public static let learnBodyCompleted: MetricKey = "learn.bodyCompleted"
    /// Дочитано історію полиці «Застосунок» — «Знаю, як усе працює».
    public static let learnAppCompleted: MetricKey = "learn.appCompleted"

    public static func part(_ index: Int) -> MetricKey {
        dayParts[max(0, min(4, index))]
    }

    public static let dayParts: [MetricKey] = [partMorning, partNoon, partAfternoon, partEvening, partNight]

    /// Значення в мілілітрах — прогрес показується в мл / л або в унціях людини, а не штуками (WAT-46,
    /// WAT-52). Кількість подій (`aggregate: .count`) лишається штуками й тут.
    public var isVolume: Bool {
        self == .intakeAdded || self == .intakeRemoved || self == .intakeRestored || self == .dayTotal
            || Self.dayParts.contains(self)
    }
}
