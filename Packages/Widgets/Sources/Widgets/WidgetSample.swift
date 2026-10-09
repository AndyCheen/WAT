import Foundation
import Core

extension WidgetSnapshot {
    /// Типовий день — для заглушки WidgetKit (галерея віджетів системи, поки даних немає) і DEBUG-галереї:
    /// чотири порції до обіду, трохи попереду темпу, серія 12, рівень 7. Як сценарій «Випереджаю» в макеті.
    public static func sample(at now: Date, calendar: CalendarService) -> WidgetSnapshot {
        let day = calendar.dayKey(for: now)
        let schedule = DaySchedule.weekdayDefault
        func at(_ minute: Int) -> Date {
            WidgetTimeline.date(of: day, minute: minute, calendar: calendar) ?? now
        }
        let nowMinute = calendar.minuteOfDay(now)
        let portions = [(495, 300), (605, 250), (700, 250), (770, 200)]
            .filter { $0.0 <= max(nowMinute, schedule.wakeMinutes) }
            .enumerated()
            .map { index, item in Portion(id: DeterministicID.uuid(from: "widget-sample-\(index)"), at: at(item.0), ml: item.1) }
        let total = portions.reduce(0) { $0 + $1.ml }
        let curve = schedule.curve(goalMl: 2000)
        let reserve = HydrationReserve.make(
            portions: portions, capacityMl: HydrationReserve.capacity(typicalPortionMl: 250), now: now,
            plannedReminder: nil, previous: nil
        ) { anchor, drunk in
            let due = curve.nextDueMinute(anchorMinute: Double(calendar.minuteOfDay(anchor)), drunkMl: drunk, portionMl: 250,
                                          k: 1, minGapMinutes: 60, maxGapMinutes: 180)
            let reminder = at(Int(due.rounded(.up)))
            return HydrationReserve.Zero(at: reminder.addingTimeInterval(-HydrationReserve.reminderLead), mode: .flowing,
                                         reminderAt: reminder)
        }
        return WidgetSnapshot(
            generatedAt: now, day: day, goalMl: 2000, totalMl: total, countedMl: total, portions: portions,
            schedule: Schedule(schedule), weekday: Schedule(schedule), homeButtons: [200, 500, 1000], glassMl: 250,
            streak: Streak(current: 12, countsToday: false),
            level: Level(level: 7, xpIntoLevel: 120, xpForNextLevel: 200),
            dailyQuests: [
                Quest(title: "Випити денну норму", progressLabel: "\(total * 100 / 2000)%",
                      fraction: Double(total) / 2000, isDone: false),
                Quest(title: "Додати 4 записи", progressLabel: portions.count >= 4 ? "Готово" : "\(portions.count)/4",
                      fraction: Double(portions.count) / 4, isDone: portions.count >= 4)
            ],
            weeklyQuests: [Quest(title: "Стрік 7 днів поспіль", progressLabel: "5/7", fraction: 5.0 / 7, isDone: false)],
            reserve: reserve
        )
    }
}
