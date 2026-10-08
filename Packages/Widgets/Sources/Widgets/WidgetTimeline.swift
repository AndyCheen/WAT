import Foundation
import Core

/// Віджети застосунку. `rawValue` — частина ідентифікатора `kind` у WidgetKit: міняти не можна,
/// інакше вже поставлені віджети зникнуть з домашнього екрана.
public enum WidgetKind: String, CaseIterable, Sendable {
    case today
    case dayPart
    case rhythm
    case reserve
    case quickAdd
    case button
    case progress
    case overview

    public var identifier: String { "com.watertracker.widget.\(rawValue)" }

    /// Як часто перемальовувати без змін у даних: крапля спадає й відлік частини доби йде, відрив від
    /// темпу змінюється з кривою. Решті вистачає ключових моментів доби.
    var cadence: TimeInterval? {
        switch self {
        case .reserve, .dayPart: return 5 * 60
        case .rhythm, .overview: return 15 * 60
        case .today, .quickAdd, .button, .progress: return nil
        }
    }
}

/// Записи таймлайну й релевантність для Smart Stack (SPEC-WIDGETS §7, §9.3). Чиста функція: час —
/// параметром, тести на фіксованих датах.
public enum WidgetTimeline {
    /// Далі за 6 год записів не будуємо — WidgetKit попросить новий таймлайн, а знімок до того часу
    /// найчастіше вже оновить застосунок.
    public static let horizon: TimeInterval = 6 * 3600
    /// Кожен запис — заархівована в'юшка; 80 вистачає на 6 год кроком 5 хв разом із ключовими моментами.
    public static let maxEntries = 80

    public static func dates(for kind: WidgetKind, snapshot: WidgetSnapshot?, from now: Date,
                             calendar: CalendarService) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        func add(_ date: Date?) {
            guard let date, date > now, date <= end else { return }
            dates.insert(date)
        }

        // Ключові моменти: північ, підйом, відбій і межі частин доби — сьогодні й завтра.
        let today = calendar.dayKey(for: now)
        for offset in 0...1 {
            let day = calendar.dayKey(offsetDays: offset, from: today)
            add(calendar.date(from: day))
            guard let snapshot else { continue }
            let schedule = schedule(of: day, in: snapshot, calendar: calendar)
            add(date(of: day, minute: schedule.wakeMinutes, calendar: calendar))
            add(date(of: day, minute: schedule.sleepMinutes, calendar: calendar))
            for block in schedule.curve(goalMl: snapshot.goalMl).goalBlocks() {
                add(date(of: day, minute: block.toMinute, calendar: calendar))
            }
        }

        if let snapshot {
            // «Скасувати» зникає саме, без нового знімка.
            add(snapshot.lastAction?.at.addingTimeInterval(WidgetSnapshot.undoWindow))
            if let reserve = snapshot.reserve, snapshot.day == today {
                add(reserve.zeroAt)
                add(reserve.reminderAt)
            }
        }

        if let step = kind.cadence {
            var limit = end
            // Порожня крапля далі не змінюється — рахувати кроки після нуля нема чого.
            if kind == .reserve, let reserve = snapshot?.reserve, snapshot?.day == today {
                limit = min(end, max(now, reserve.zeroAt))
            }
            var next = now.addingTimeInterval(step)
            while next <= limit {
                add(next)
                next = next.addingTimeInterval(step)
            }
        }
        return Array(dates.sorted().prefix(maxEntries))
    }

    /// Релевантність для Smart Stack: віджет піднімається, коли час пити, коли частина доби спливає,
    /// а ціль не закрито, і ввечері з незакритою нормою.
    public static func relevance(_ day: WidgetDay) -> Float {
        guard day.phase == .active, !day.goalMet else { return 0 }
        if day.reserve != nil, day.reserveIsEmpty { return 1 }
        if day.dayRhythmEnabled, let part = day.part, !part.isReached, part.minutesLeft <= 45 { return 0.8 }
        if day.minute >= 19 * 60 { return 0.6 }
        return 0.1
    }

    /// Розклад доби: знімка — як записано, інших — за правилом вихідних.
    static func schedule(of day: DayKey, in snapshot: WidgetSnapshot, calendar: CalendarService) -> DaySchedule {
        if day == snapshot.day { return snapshot.schedule.daySchedule }
        let week = calendar.isWeekend(day) ? (snapshot.weekend ?? snapshot.weekday) : snapshot.weekday
        return week.daySchedule
    }

    /// Момент із хвилини доби — через календарні компоненти, а не секунди від півночі: у день переведення
    /// годинника інакше все з'їхало б на годину (як `DayFrame` у сповіщеннях).
    public static func date(of day: DayKey, minute: Int, calendar service: CalendarService) -> Date? {
        if minute >= 24 * 60 { return service.date(from: service.dayKey(offsetDays: 1, from: day)) }
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = minute / 60
        parts.minute = minute % 60
        return service.calendar.date(from: parts)
    }
}
