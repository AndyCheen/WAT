import Foundation
import Core

/// Один день плану: активні години, крива темпу, моменти фіксованих типів і тихі вікна.
///
/// Час усередині — хвилини від локальної півночі, як у `PaceCurve`; у `Date` перетворюється
/// через календарні компоненти, а не секунди від початку доби — інакше в день переведення
/// годинника все з'їхало б на годину.
struct DayFrame {
    let day: DayKey
    let calendar: Calendar
    let dayStart: Date
    let wake: Date
    let sleep: Date
    let curve: PaceCurve
    let morningAt: Date
    let eveningAt: Date
    /// Кінець нагадувань: далі працює вечірній підсумок (§6.2).
    let cutoff: Date
    let quiet: [Range<Date>]
    let isWeekend: Bool

    init(day: DayKey, calendar service: CalendarService, goalMl: Int,
         preferences: NotificationPreferences, rules: NotificationRules) {
        self.day = day
        let calendar = service.calendar
        self.calendar = calendar
        self.dayStart = service.date(from: day)
        let weekday = Self.weekdayIndex(of: dayStart, calendar: calendar)
        isWeekend = weekday >= 5

        let schedule = preferences.schedule(isWeekend: isWeekend)
        let wakeMinute = max(0, min(schedule.wakeMinutes, 24 * 60))
        let sleepMinute = max(wakeMinute, min(schedule.sleepMinutes, 24 * 60))
        curve = PaceCurve(goalMl: goalMl, wakeMinutes: wakeMinute, sleepMinutes: sleepMinute)

        func at(_ minute: Int) -> Date { Self.date(day: day, minute: Double(minute), service: service) }
        wake = at(wakeMinute)
        sleep = at(sleepMinute)

        let morningMinute = min(max(preferences.morningMinutes ?? wakeMinute, wakeMinute), sleepMinute)
        morningAt = at(morningMinute)
        let eveningMinute = min(max(preferences.eveningMinutes ?? sleepMinute - rules.eveningLeadMinutes, wakeMinute), sleepMinute)
        eveningAt = at(eveningMinute)
        cutoff = preferences.eveningEnabled
            ? eveningAt
            : at(max(wakeMinute, sleepMinute - rules.cutoffWithoutEveningMinutes))

        quiet = preferences.quietWindows
            .filter { $0.applies(toWeekday: weekday) }
            .flatMap { window -> [Range<Date>] in
                // Період через північ (22:00–07:00) у межах доби — два шматки.
                if window.fromMinutes < window.toMinutes {
                    return [at(window.fromMinutes)..<at(window.toMinutes)]
                }
                return [at(0)..<at(window.toMinutes), at(window.fromMinutes)..<at(24 * 60)]
            }
            .filter { !$0.isEmpty }
        self.service = service
    }

    private let service: CalendarService

    /// Дата з хвилини доби (може бути дробовою).
    func date(minute: Double) -> Date {
        Self.date(day: day, minute: minute, service: service)
    }

    /// Хвилина доби для моменту цього дня.
    func minute(of date: Date) -> Double {
        if date <= dayStart { return 0 }
        let parts = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: date)
        guard calendar.isDate(date, inSameDayAs: dayStart) else { return 24 * 60 }
        let seconds = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1e9
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + seconds / 60
    }

    /// Округлення вгору до хвилини — у ТЗ 11:08:15 означає «11:09» (§6.1). Запас на похибку
    /// `Double`, щоб рівно ціла хвилина не стала наступною.
    func ceilToMinute(_ minute: Double) -> Double {
        (minute - 1e-6).rounded(.up)
    }

    /// Момент з урахуванням тихих періодів: потрапив усередину — зсувається на кінець періоду;
    /// якщо після зсуву вже пізно (≥ `limit` або поза активними годинами) — `nil` (§6.2, §13.2).
    func place(_ date: Date, limit: Date) -> Date? {
        var t = date
        var moved = true
        while moved {
            moved = false
            for window in quiet where window.contains(t) {
                t = window.upperBound
                moved = true
            }
        }
        guard t >= wake, t < limit, t < sleep else { return nil }
        return t
    }

    /// `HHmm` — слот нагадування в ідентифікаторі.
    func clockSlot(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func date(day: DayKey, minute: Double, service: CalendarService) -> Date {
        let whole = Int(minute.rounded(.down))
        let fraction = minute - Double(whole)
        let base: DayKey = whole >= 24 * 60 ? service.dayKey(offsetDays: whole / (24 * 60), from: day) : day
        let local = whole % (24 * 60)
        var parts = DateComponents()
        parts.year = base.year; parts.month = base.month; parts.day = base.day
        parts.hour = local / 60; parts.minute = local % 60
        let date = service.calendar.date(from: parts) ?? service.date(from: base)
        return date.addingTimeInterval(fraction * 60)
    }

    /// 0 — понеділок … 6 — неділя.
    static func weekdayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}
