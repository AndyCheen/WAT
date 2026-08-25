import Foundation
import SwiftData
import Core
import Persistence
import Metrics
@testable import Gamification

@MainActor
struct GameEnv {
    let container: ModelContainer
    let clock: FixedClock
    let calendar: CalendarService
    let metrics: MetricsService
    let store: GamificationStore
    let dayLogs: DayLogRepository
    let profiles: ProfileRepository
    let game: GamificationService

    init(day: Int = 18, hour: Int = 14, goalMl: Int = 2000) {
        container = Database.makeInMemoryContainer()
        let context = container.mainContext
        clock = FixedClock(now: Self.date(day: day, hour: hour))
        calendar = CalendarService(clock: clock)
        metrics = MetricsService(store: MetricStore(context: context), calendar: calendar)
        store = GamificationStore(context: context)
        dayLogs = DayLogRepository(context: context)
        profiles = ProfileRepository(context: context)
        profiles.setGoal(goalMl, source: .seed, effectiveFrom: DayKey(rawValue: "2020-01-01"), at: clock.now)
        game = GamificationService(
            store: store, dayLogs: dayLogs, profiles: profiles,
            metrics: metrics, calendar: calendar
        )
        game.bootstrap()
    }

    static func date(day: Int, hour: Int, month: Int = 7, year: Int = 2026) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    /// Імітує «повністю закритий день» без залучення модуля Hydration.
    func completeDay(_ key: String, goalMl: Int = 2000, hour: Int = 12) {
        let day = DayKey(rawValue: key)
        let log = dayLogs.dayLog(for: day, goalMl: goalMl, timeZoneId: "Europe/Kyiv")
        log.totalMl = goalMl
        log.countedMl = goalMl
        log.entriesCount = 4
        dayLogs.save()

        let date = Self.date(day: day.day, hour: hour, month: day.month, year: day.year)
        metrics.record(MetricEvent(
            name: .dayGoalMet, value: 1, occurredAt: date,
            sourceRef: DeterministicID.uuid(from: "day.goalMet:\(key)")
        ))
    }

    func addIntakeEvent(_ ml: Int, hour: Int = 10, day: Int = 18) -> UUID {
        let ref = UUID()
        let date = Self.date(day: day, hour: hour)
        metrics.record(MetricEvent(name: .intakeAdded, value: Double(ml), occurredAt: date, sourceRef: ref))
        metrics.record(MetricEvent(name: .intakeCount, value: 1, occurredAt: date, sourceRef: ref))
        return ref
    }
}
