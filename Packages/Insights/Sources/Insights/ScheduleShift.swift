import Foundation
import Core
import Persistence

/// Пороги пропозиції графіка (WAT-41, SPEC-NOTIFICATIONS §27) — як `XPRules`: усі числа тут,
/// щоб перебалансувати, не чіпаючи логіку.
public struct ScheduleShiftRules: Sendable, Equatable {
    /// Повні дні до сьогодні: сьогоднішній ще не закінчився, його остання склянка невідома.
    public var windowDays = 14
    /// Днів із порціями у вікні. Заодно виключає перший тиждень користування: 8 активних днів
    /// до сьогодні неможливі раніше ніж на 9-й день.
    public var minActiveDays = 8
    /// Вихідних у 14 днях лише 4 — судити про них можна з трьох.
    public var minWeekendDays = 3
    /// На скільки звичка має відходити від графіка, щоб це був зсув.
    public var shiftMinutes = 45
    /// У скількох відсотках днів. Більше половини — тож і медіана тоді за порогом.
    public var minSharePercent = 70
    /// Нормальна пауза між останньою склянкою й сном (§13.6). Раніше за неї закінчити — не зсув.
    public var eveningPauseMinutes = 120
    // Частота показу (§27): «Так» — не частіше ніж раз на 30 днів, «Ні» — 60 днів, якщо зсув не виріс
    // на 60 хв, закрили без відповіді — 7.
    public var minIntervalDays = 30
    public var declinedDays = 60
    public var dismissedDays = 7
    public var regrowthMinutes = 60

    public init() {}

    public static let standard = ScheduleShiftRules()
}

/// Один день вікна: чи вихідний і хвилини порцій від 00:00.
public struct ScheduleDay: Sendable, Equatable {
    public let isWeekend: Bool
    public let intakeMinutes: [Int]

    public init(isWeekend: Bool, intakeMinutes: [Int]) {
        self.isWeekend = isWeekend
        self.intakeMinutes = intakeMinutes
    }
}

/// Пропозиція змінити розклад однієї групи днів.
public struct ScheduleSuggestion: Sendable, Equatable {
    public enum Scope: Sendable, Equatable {
        /// Увесь графік: окремого розкладу вихідних немає, і вихідні йдуть за буднями.
        case everyDay
        /// Будні; розклад вихідних уже окремий і лишається.
        case weekdays
        /// Будні, а вихідні з даними, але без зсуву, лишаються як були: окремий розклад вмикається
        /// зі старими часами, щоб не будити о 06:30 у суботу.
        case weekdaysOnly
        /// Окремий розклад вихідних — вмикається, якщо був вимкнений.
        case weekends
    }

    public let scope: Scope
    /// Розклад групи зараз і запропонований.
    public let current: DaySchedule
    public let proposed: DaySchedule

    public init(scope: Scope, current: DaySchedule, proposed: DaySchedule) {
        self.scope = scope
        self.current = current
        self.proposed = proposed
    }

    /// Найбільший зсув межі — для правила «Ні»: питати знову раніше, лише якщо він виріс на 60 хв.
    public var shiftMinutes: Int {
        max(abs(proposed.wakeMinutes - current.wakeMinutes), abs(proposed.sleepMinutes - current.sleepMinutes))
    }

    /// Увесь розклад після згоди з `schedule` — запропонованим чи підправленим у «Налаштувати».
    public func applying(_ schedule: DaySchedule, to week: WeekSchedule) -> WeekSchedule {
        var next = week
        switch scope {
        case .everyDay, .weekdays:
            next.weekday = schedule
        case .weekdaysOnly:
            next.weekendEnabled = true
            next.weekend = current
            next.weekday = schedule
        case .weekends:
            next.weekendEnabled = true
            next.weekend = schedule
        }
        return next
    }
}

/// Чи людина стабільно живе за іншим графіком (WAT-41, SPEC-NOTIFICATIONS §27). Чиста функція:
/// дні приходять значеннями, тести — на фікстурах без бази.
public enum ScheduleShift {

    /// Будні й вихідні рахуються окремо, кожна група — проти свого розкладу. Пропозиція одна:
    /// будні важливіші (їх більше), вихідні — коли зсув лише в них.
    public static func suggest(days: [ScheduleDay], current week: WeekSchedule,
                               rules: ScheduleShiftRules = .standard) -> ScheduleSuggestion? {
        // Порція до 04:00 — ще вчорашній вечір (доба застосунку закінчується опівночі), а не ранок:
        // о 00:30 людина ще не лягла, а не вже встала. День лише з такими порціями — без доказів.
        let active = days
            .map { ScheduleDay(isWeekend: $0.isWeekend, intakeMinutes: $0.intakeMinutes.filter { $0 >= DaySchedule.earliestWakeMinutes }) }
            .filter { !$0.intakeMinutes.isEmpty }
        guard active.count >= rules.minActiveDays else { return nil }

        let weekdaySchedule = week.weekday
        let weekendSchedule = week.schedule(isWeekend: true)
        let weekdays = shift(of: active.filter { !$0.isWeekend }, against: weekdaySchedule, minDays: 1, rules: rules)
        let weekends = shift(of: active.filter(\.isWeekend), against: weekendSchedule, minDays: rules.minWeekendDays, rules: rules)

        if case .shifted(let proposed) = weekdays {
            let scope: ScheduleSuggestion.Scope
            if week.weekendEnabled {
                scope = .weekdays
            } else {
                // Вихідні без даних ідуть за буднями: доказу, що вони інші, немає.
                scope = weekends == .steady ? .weekdaysOnly : .everyDay
            }
            return ScheduleSuggestion(scope: scope, current: weekdaySchedule, proposed: proposed)
        }
        if case .shifted(let proposed) = weekends {
            return ScheduleSuggestion(scope: .weekends, current: weekendSchedule, proposed: proposed)
        }
        return nil
    }

    enum GroupShift: Equatable {
        /// Замало днів, щоб судити.
        case unknown
        /// Дні є, зсуву немає.
        case steady
        case shifted(DaySchedule)
    }

    /// Ранок — в обидва боки: о першій склянці людина точно не спить, тож підйом — медіана першої склянки.
    /// Вечір пізніше — відбій = медіана останньої. Вечір раніше — лише понад нормальну паузу 2 год (§13.6),
    /// і тоді відбій = остання склянка + 2 год.
    static func shift(of days: [ScheduleDay], against schedule: DaySchedule, minDays: Int,
                      rules: ScheduleShiftRules) -> GroupShift {
        guard !days.isEmpty, days.count >= minDays else { return .unknown }
        let firsts = days.compactMap { $0.intakeMinutes.min() }
        let lasts = days.compactMap { $0.intakeMinutes.max() }
        let step = rules.shiftMinutes
        func mostly(_ values: [Int], _ condition: (Int) -> Bool) -> Bool {
            values.filter(condition).count * 100 >= values.count * rules.minSharePercent
        }

        var wake = schedule.wakeMinutes
        var sleep = schedule.sleepMinutes
        if mostly(firsts, { $0 <= schedule.wakeMinutes - step }) || mostly(firsts, { $0 >= schedule.wakeMinutes + step }) {
            wake = rounded(median(firsts))
        }
        if mostly(lasts, { $0 >= schedule.sleepMinutes + step }) {
            sleep = min(DaySchedule.latestSleepMinutes, rounded(median(lasts)))
        } else if mostly(lasts, { $0 <= schedule.sleepMinutes - rules.eveningPauseMinutes - step }) {
            sleep = rounded(median(lasts) + Double(rules.eveningPauseMinutes))
        }

        // Активних годин ≥ 6, як на екрані «Сповіщення». Пізній підйом разом із раннім відбоєм не стискає
        // день — поступається відбій; зсув, що після цього став меншим за поріг, — не зсув.
        if sleep - wake < DaySchedule.minActiveMinutes {
            sleep = min(DaySchedule.latestSleepMinutes, wake + DaySchedule.minActiveMinutes)
        }
        if abs(sleep - schedule.sleepMinutes) < step { sleep = schedule.sleepMinutes }
        if sleep - wake < DaySchedule.minActiveMinutes { wake = sleep - DaySchedule.minActiveMinutes }
        if abs(wake - schedule.wakeMinutes) < step { wake = schedule.wakeMinutes }

        let proposed = DaySchedule(wakeMinutes: wake, sleepMinutes: sleep)
        return proposed == schedule ? .steady : .shifted(proposed)
    }

    static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? Double(sorted[middle]) : Double(sorted[middle - 1] + sorted[middle]) / 2
    }

    /// До найближчих 15 хв — крок налаштувань.
    static func rounded(_ minutes: Double) -> Int {
        Int((minutes / Double(DaySchedule.stepMinutes)).rounded()) * DaySchedule.stepMinutes
    }
}

/// Чи можна показати вікно сьогодні (SPEC-NOTIFICATIONS §27).
public enum ScheduleOfferPolicy {

    /// - Parameters:
    ///   - shift: зсув нової пропозиції, хв.
    ///   - daysSinceShown: днів від останнього показу; `nil` — ще не показували.
    ///   - answeredShift: зсув, який бачили під час останнього показу.
    public static func canOffer(shift: Int, last outcome: ScheduleOfferOutcome, daysSinceShown: Int?,
                                answeredShift: Int, rules: ScheduleShiftRules = .standard) -> Bool {
        guard let days = daysSinceShown else { return true }
        switch outcome {
        case .none:
            return true
        case .dismissed:
            return days >= rules.dismissedDays
        case .accepted:
            return days >= rules.minIntervalDays
        case .declined:
            // «Ні» — до 60 днів тиші. Раніше — лише якщо звичка відійшла ще далі, і все одно не частіше
            // ніж раз на 30 днів.
            return days >= rules.declinedDays
                || (days >= rules.minIntervalDays && shift >= answeredShift + rules.regrowthMinutes)
        }
    }
}
