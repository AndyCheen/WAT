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
        let glasses = portions.filter { $0.ml >= 150 }.count
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
            // Опівдні заглушки обидва ще в роботі — так у галереї системи видно рядки, а не «✓ Усе на сьогодні».
            dailyQuests: [
                Quest(title: "¾ норми до 17:30", progressLabel: total >= 1500 ? "Готово" : WidgetPresenter.left(1500 - total),
                      fraction: min(1, Double(total) / 1500), isDone: total >= 1500, expiresAt: at(17 * 60 + 30)),
                Quest(title: "5 склянок від 150 мл", progressLabel: glasses >= 5 ? "Готово" : "\(glasses)/5",
                      fraction: min(1, Double(glasses) / 5), isDone: glasses >= 5)
            ],
            weeklyQuests: [Quest(title: "Норма 5 днів", progressLabel: "3/5 дн.", fraction: 3.0 / 5, isDone: false)],
            reserve: reserve
        )
    }
}
