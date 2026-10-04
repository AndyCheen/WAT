import Foundation
import Core
import Persistence
@testable import Notifications

/// 1 жовтня 2026 — четвер. Норма 2000 мл, 08:00–22:00, склянка 250 мл — як у §6.1.
enum Fixture {
    static let kyiv = TimeZone(identifier: "Europe/Kyiv")!

    static func date(day: Int = 1, _ hour: Int, _ minute: Int = 0, month: Int = 10, zone: TimeZone = kyiv) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = month; parts.day = day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: parts)!
    }

    static func clock(_ date: Date, zone: TimeZone = kyiv) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    static func context(at now: Date, countedMl: Int = 0, intakes: [Date] = []) -> NotificationContext {
        NotificationContext(now: now, timeZone: kyiv, goalMl: 2000, countedMl: countedMl,
                            intakesToday: intakes, lastIntakeAt: intakes.max())
    }
}

/// Проганяє день подія за подією: на кожній порції план перебудовується, а між подіями
/// доставляється рівно те, що було заплановано, — так само, як у реальному застосунку, де код
/// у момент доставки не виконується (§16.1).
struct DaySimulator {
    var preferences = NotificationPreferences.default
    var rules = NotificationRules.default
    var base: (Date) -> NotificationContext = { Fixture.context(at: $0) }

    /// Усе доставлене за день, у порядку часу.
    func run(intakes: [(date: Date, ml: Int)], from start: Date, until end: Date,
             journal initial: NotificationJournal = .empty) -> [PlannedNotification] {
        var journal = initial
        var delivered: [PlannedNotification] = []
        var drank = 0
        var times: [Date] = []
        var now = start
        let events = intakes.sorted { $0.date < $1.date }

        for index in 0...events.count {
            var context = base(now)
            context.countedMl = min(drank, Int(Double(context.goalMl) * 1.2))
            context.intakesToday = times
            context.lastIntakeAt = times.max() ?? context.lastIntakeAt
            let plan = NotificationPlanner.plan(context: context, preferences: preferences, journal: journal, rules: rules)

            let next = index < events.count ? events[index].date : end
            for item in plan.items where item.fireAt > now && item.fireAt <= next {
                delivered.append(item)
                journal.entries.append(JournalEntry(
                    identifier: item.id, type: item.type, slot: item.slot, dayKey: item.dayKey,
                    fireAt: item.fireAt, variant: item.variant, status: .delivered
                ))
            }
            guard index < events.count else { break }
            drank += events[index].ml
            times.append(events[index].date)
            now = events[index].date
        }
        return delivered
    }

    func reminders(intakes: [(date: Date, ml: Int)], from start: Date = Fixture.date(7),
                   until end: Date = Fixture.date(23, 59)) -> [String] {
        run(intakes: intakes, from: start, until: end).filter { $0.type == .reminder }.map { Fixture.clock($0.fireAt) }
    }
}

func intakes(_ list: [(Int, Int, Int)], day: Int = 1) -> [(date: Date, ml: Int)] {
    list.map { (Fixture.date(day: day, $0.0, $0.1), $0.2) }
}
