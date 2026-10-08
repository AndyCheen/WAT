import Foundation
import Core
@testable import Widgets

/// Середа, 8 жовтня 2026, Київ — як у макеті `Design/Widgets.html`.
enum Fixture {
    static let zone = TimeZone(identifier: "Europe/Kyiv")!
    static let clock = FixedClock(now: date(13, 25), timeZone: zone)
    static let calendar = CalendarService(clock: clock)
    static let day = DayKey(rawValue: "2026-10-08")

    static func date(_ hour: Int, _ minute: Int, day: Int = 8) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static func portion(_ hour: Int, _ minute: Int, _ ml: Int, id: Int) -> WidgetSnapshot.Portion {
        WidgetSnapshot.Portion(id: uuid(id), at: date(hour, minute), ml: ml)
    }

    static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    /// Сценарій «Випереджаю» з макета: 300 + 250 + 250 + 200 до 12:50.
    static let aheadPortions = [
        portion(8, 15, 300, id: 1), portion(10, 5, 250, id: 2), portion(11, 40, 250, id: 3), portion(12, 50, 200, id: 4)
    ]

    static func snapshot(portions: [WidgetSnapshot.Portion] = aheadPortions, goal: Int = 2000,
                         rhythm: Bool = true, reserve: HydrationReserve? = nil,
                         lastAction: WidgetSnapshot.LastAction? = nil,
                         streak: WidgetSnapshot.Streak = .init(current: 12, countsToday: false)) -> WidgetSnapshot {
        let total = portions.reduce(0) { $0 + $1.ml }
        let schedule = WidgetSnapshot.Schedule(DaySchedule.weekdayDefault)
        return WidgetSnapshot(
            generatedAt: date(13, 25), day: day, goalMl: goal, totalMl: total,
            countedMl: min(total, goal * 12 / 10), portions: portions, schedule: schedule, weekday: schedule,
            weekend: WidgetSnapshot.Schedule(wakeMinutes: 10 * 60, sleepMinutes: 23 * 60),
            dayRhythmEnabled: rhythm, homeButtons: [200, 500, 1000], glassMl: 250, streak: streak,
            level: .init(level: 7, xpIntoLevel: 120, xpForNextLevel: 200), reserve: reserve, lastAction: lastAction
        )
    }

    /// Нуль за темпом (§6.2, частота «звичайно», P = 250) — як рахує `Features`.
    static func paceZero(goal: Int = 2000) -> (Date, Int) -> HydrationReserve.Zero {
        let curve = DaySchedule.weekdayDefault.curve(goalMl: goal)
        return { anchor, drunk in
            if drunk >= goal { return .init(at: date(22, 0), mode: .goalMet) }
            let minute = Double(calendar.minuteOfDay(anchor))
            let due = curve.nextDueMinute(anchorMinute: minute, drunkMl: drunk, portionMl: 250,
                                          k: 1, minGapMinutes: 60, maxGapMinutes: 180)
            guard due < 20 * 60 else { return .init(at: date(22, 0), mode: .evening) }
            let reminder = date(0, 0).addingTimeInterval(due.rounded(.up) * 60)
            return .init(at: reminder.addingTimeInterval(-HydrationReserve.reminderLead), mode: .flowing, reminderAt: reminder)
        }
    }
}
