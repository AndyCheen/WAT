import Foundation
import SwiftData
import Core
import Persistence
import Metrics
@testable import Hydration

/// Мінімальне середовище для доменних тестів: in-memory БД + фіксований час.
@MainActor
struct TestEnv {
    let container: ModelContainer
    let clock: FixedClock
    let calendar: CalendarService
    let profiles: ProfileRepository
    let dayLogs: DayLogRepository
    let metrics: MetricsService
    let hydration: HydrationService

    init(day: Int = 18, hour: Int = 14, goalMl: Int = 2000) {
        container = Database.makeInMemoryContainer()
        let context = container.mainContext
        clock = FixedClock(now: Self.date(day: day, hour: hour))
        calendar = CalendarService(clock: clock)
        profiles = ProfileRepository(context: context)
        dayLogs = DayLogRepository(context: context)
        metrics = MetricsService(store: MetricStore(context: context), calendar: calendar)
        hydration = HydrationService(
            dayLogs: dayLogs, profiles: profiles, metrics: metrics, calendar: calendar
        )
        profiles.setGoal(goalMl, source: .seed, effectiveFrom: DayKey(rawValue: "2020-01-01"), at: clock.now)
    }

    static func date(day: Int, hour: Int, minute: Int = 0, month: Int = 7, year: Int = 2026) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    func at(day: Int = 18, hour: Int, minute: Int = 0) -> Date {
        Self.date(day: day, hour: hour, minute: minute)
    }
}
