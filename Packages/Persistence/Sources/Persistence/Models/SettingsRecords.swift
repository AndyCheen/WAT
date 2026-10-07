import Foundation
import SwiftData
import Core

/// Де живе кнопка-пресет: на головному чи підказкою в шторці «Інше» (WAT-45).
public enum PresetPlace: Int, CaseIterable, Sendable {
    case home = 0
    case customSheet = 1

    /// Кількість фіксована: три кнопки з «Інше» складають сітку 2×2, чотири чипи — ширину шторки.
    /// В унціях — звичні там порції (чашка 8 унц., пляшка 16 унц., кварта 32 унц.), а не перераховані мілілітри:
    /// «7 унц. · 17 унц. · 34 унц.» виглядали б випадковими (WAT-46).
    public func defaults(for unit: VolumeUnit) -> [Int] {
        guard !unit.isMetric else {
            switch self {
            case .home: return [200, 500, 1000]
            case .customSheet: return [150, 250, 350, 500]
            }
        }
        let ounces = self == .home ? [8, 16, 32] : [6, 8, 12, 16]
        return ounces.map { unit.milliliters(units: $0) }
    }
}

/// Кнопки швидкого додавання на головному й підказки шторки «Інше» (ТЗ §4.1 — редаговані, WAT-45).
@Model
public final class QuickAddPreset {
    public var id: UUID = UUID()
    /// `PresetPlace`; типове 0 — рядки зі старих БД, коли пресети були лише на головному.
    public var placeRaw: Int = PresetPlace.home.rawValue
    public var order: Int = 0
    public var amountMl: Int = 200
    public var enabled: Bool = true

    public init(id: UUID = UUID(), place: PresetPlace = .home, order: Int, amountMl: Int, enabled: Bool = true) {
        self.id = id
        self.placeRaw = place.rawValue
        self.order = order
        self.amountMl = amountMl
        self.enabled = enabled
    }

    public var place: PresetPlace { PresetPlace(rawValue: placeRaw) ?? .home }
}

/// Тихий період: дні тижня + від–до (SPEC-NOTIFICATIONS §13.2). Те, що потрапило всередину,
/// зсувається на кінець періоду або скасовується.
///
/// Колишній `NotificationRule`: його поля якраз мали цю форму, а режими `smart/fixed/…`
/// виявились не типами сповіщень (§2, п. 2). Застосунок не випущений — міграції немає.
@Model
public final class QuietPeriod {
    public var id: UUID = UUID()
    public var order: Int = 0
    /// Біт 0 — понеділок … біт 6 — неділя, як і тиждень у застосунку.
    public var weekdayMask: Int = 0b1111111
    public var fromMinutes: Int = 9 * 60
    public var toMinutes: Int = 12 * 60
    public var enabled: Bool = true

    public init(id: UUID = UUID(), order: Int, weekdayMask: Int = 0b1111111,
                fromMinutes: Int, toMinutes: Int, enabled: Bool = true) {
        self.id = id
        self.order = order
        self.weekdayMask = weekdayMask
        self.fromMinutes = fromMinutes
        self.toMinutes = toMinutes
        self.enabled = enabled
    }

    public static let allDays = 0b1111111
}

/// Налаштування сповіщень за типами — один рядок (SPEC-NOTIFICATIONS §15.1, етапи A і B).
///
/// Головний вимикач, режим дня й склянка живуть у `UserProfile`; тут — лише те, що
/// стосується самих сповіщень, і службовий стан (пауза, запит дозволу, остання взаємодія).
@Model
public final class NotificationSettings {
    public var remindersEnabled: Bool = true
    public var reminderModeRaw: Int = ReminderMode.pace.rawValue
    public var reminderFrequencyRaw: Int = ReminderFrequency.normal.rawValue
    public var reminderIntervalMinutes: Int = 90
    public var followUpEnabled: Bool = true

    public var morningEnabled: Bool = true
    /// `nil` — «о підйомі».
    public var morningCustomMinutes: Int?

    public var eveningEnabled: Bool = true
    /// `nil` — «за 2 год до відбою».
    public var eveningCustomMinutes: Int?

    /// Чекпоінти частин доби (§9, етап B).
    public var checkpointsEnabled: Bool = true

    // Звіти (§11.1, етап B). Денний — о відбої, тихо; тижневий і місячний — о заданій годині.
    public var dailyReportEnabled: Bool = true
    public var weeklyReportEnabled: Bool = true
    /// 0 — понеділок … 6 — неділя.
    public var weeklyReportWeekday: Int = 0
    public var weeklyReportMinutes: Int = 10 * 60
    public var monthlyReportEnabled: Bool = true
    public var monthlyReportMinutes: Int = 10 * 60

    public var rescueEnabled: Bool = true
    public var echoEnabled: Bool = true
    public var comebackEnabled: Bool = true

    public var soundRaw: Int = NotificationSound.bubble.rawValue

    /// «Не сьогодні» — до найближчої півночі (§13.2).
    public var pausedUntil: Date?

    public var permissionPromptStateRaw: Int = PermissionPromptState.notAsked.rawValue
    public var permissionPromptPostponedAt: Date?

    /// Відкриття застосунку чи дія в ньому: ланцюг нагадувань стартує не раніше ніж через
    /// 30 хв після неї, а лічильник проігнорованих обнуляється (§6.2, «Скидання»).
    public var lastInteractionAt: Date?

    public init() {}

    public var reminderMode: ReminderMode {
        get { ReminderMode(rawValue: reminderModeRaw) ?? .pace }
        set { reminderModeRaw = newValue.rawValue }
    }

    public var reminderFrequency: ReminderFrequency {
        get { ReminderFrequency(rawValue: reminderFrequencyRaw) ?? .normal }
        set { reminderFrequencyRaw = newValue.rawValue }
    }

    public var sound: NotificationSound {
        get { NotificationSound(rawValue: soundRaw) ?? .bubble }
        set { soundRaw = newValue.rawValue }
    }

    public var permissionPromptState: PermissionPromptState {
        get { PermissionPromptState(rawValue: permissionPromptStateRaw) ?? .notAsked }
        set { permissionPromptStateRaw = newValue.rawValue }
    }

    public static let intervalChoices = [60, 90, 120, 180]
}

/// Журнал сповіщень: один рядок на кожне заплановане (SPEC-NOTIFICATIONS §16.8).
///
/// З нього рахуються стани з §3.2 (доставлено, виконано, відкладено…), денний ліміт,
/// ротація текстів і ідемпотентність дій: друга відповідь на те саме сповіщення бачить
/// `respondedAt` і порцію не додає.
@Model
public final class NotificationLog {
    public var id: UUID = UUID()
    /// `wt.<тип>.<dayKey>.<слот>` — той самий, що в запиті `UNNotificationRequest`.
    @Attribute(.unique) public var identifier: String = ""
    public var typeRaw: Int = NotificationType.reminder.rawValue
    public var dayKey: String = ""
    public var fireAt: Date = Date.distantPast
    public var plannedAt: Date = Date.distantPast
    public var cancelledAt: Date?
    public var deliveredAt: Date?
    /// Настало, коли застосунок був відкритий, тому не показане (§16.7).
    public var suppressedAt: Date?
    public var openedAt: Date?
    public var respondedAt: Date?
    public var responseRaw: Int = NotificationResponseKind.none.rawValue
    public var intakeId: UUID?
    /// Номер варіанта тексту — для ротації «не два останні поспіль» (§14.1).
    public var variant: Int = 0
    /// Ситуація всередині типу (основне / повторне, «можна закрити» / «заспокійливе»…).
    public var slot: String = ""

    public init(id: UUID = UUID(), identifier: String, type: NotificationType, slot: String,
                dayKey: String, fireAt: Date, plannedAt: Date, variant: Int) {
        self.id = id
        self.identifier = identifier
        self.typeRaw = type.rawValue
        self.slot = slot
        self.dayKey = dayKey
        self.fireAt = fireAt
        self.plannedAt = plannedAt
        self.variant = variant
    }

    public var type: NotificationType { NotificationType(rawValue: typeRaw) ?? .reminder }

    public var response: NotificationResponseKind {
        get { NotificationResponseKind(rawValue: responseRaw) ?? .none }
        set { responseRaw = newValue.rawValue }
    }
}
