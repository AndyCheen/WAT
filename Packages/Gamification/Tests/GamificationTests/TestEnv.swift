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

    static func date(day: Int, hour: Int, minute: Int = 0, month: Int = 7, year: Int = 2026) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
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

    /// Справжня порція в денному лозі + події — як у `HydrationService`, але без нього:
    /// XP за частину доби рахує порції за часом, тож однієї події тут замало.
    @discardableResult
    func addIntake(_ ml: Int, hour: Int, minute: Int = 0, day: Int = 18) -> UUID {
        let date = Self.date(day: day, hour: hour, minute: minute)
        let key = calendar.dayKey(for: date)
        let log = dayLogs.dayLog(for: key, goalMl: 2000, timeZoneId: "Europe/Kyiv")
        // Як `HydrationService`: розклад дня — знімок профілю в момент порції.
        log.scheduleSnapshot = profiles.profile().schedule(isWeekend: calendar.isWeekend(key))
        let intake = Intake(amountMl: ml, createdAt: date)
        dayLogs.insert(intake, into: log)
        recomputeTotals(log)
        dayLogs.save()
        publishIntake(intake)
        return intake.id
    }

    func removeIntake(_ id: UUID) {
        guard let intake = dayLogs.intake(id: id) else { return }
        intake.deletedAt = clock.now
        if let log = intake.dayLog { recomputeTotals(log) }
        dayLogs.save()
        metrics.revert(sourceRef: id, at: clock.now)
        metrics.commit()
    }

    func restoreIntake(_ id: UUID) {
        guard let intake = dayLogs.intake(id: id) else { return }
        intake.deletedAt = nil
        if let log = intake.dayLog { recomputeTotals(log) }
        dayLogs.save()
        publishIntake(intake)
    }

    /// Як `HydrationService.recompute`: XP за воду рахується від зарахованого об'єму дня (SPEC-PRIZES §16.13).
    /// `entriesCount` не чіпаємо — на ньому подарунок за повернення, і тести на нього мають власний хелпер.
    private func recomputeTotals(_ log: DayLog) {
        let total = (log.intakes ?? []).filter { !$0.isDeleted }.reduce(0) { $0 + $1.amountMl }
        log.totalMl = total
        log.countedMl = min(total, log.capMl)
    }

    private func publishIntake(_ intake: Intake) {
        metrics.record(MetricEvent(name: .intakeAdded, value: Double(intake.amountMl), occurredAt: intake.createdAt, sourceRef: intake.id))
        metrics.record(MetricEvent(name: .intakeCount, value: 1, occurredAt: intake.createdAt, sourceRef: intake.id))
        metrics.commit()
    }

    /// Лише події, без порції в лозі, — але з об'ємом дня: від нього XP за воду (SPEC-PRIZES §16.13).
    @discardableResult
    func addIntakeEvent(_ ml: Int, hour: Int = 10, day: Int = 18) -> UUID {
        let ref = UUID()
        let date = Self.date(day: day, hour: hour)
        let log = dayLogs.dayLog(for: calendar.dayKey(for: date), goalMl: 2000, timeZoneId: "Europe/Kyiv")
        log.totalMl += ml
        log.countedMl = min(log.totalMl, log.capMl)
        dayLogs.save()
        metrics.record(MetricEvent(name: .intakeAdded, value: Double(ml), occurredAt: date, sourceRef: ref))
        metrics.record(MetricEvent(name: .intakeCount, value: 1, occurredAt: date, sourceRef: ref))
        return ref
    }
}

extension GameEnv {
    /// Рівень без порцій: XP «за завдання» рівно до порогу рівня, потім видача призів, як після дії.
    func reachLevel(_ level: Int, at date: Date? = nil) {
        let need = LevelCalculator.totalXpRequired(forLevel: level, curve: game.xp.curve) - game.levelProgress().totalXp
        guard need > 0 else { return }
        game.xp.award(amount: need, reason: .questCompleted, refId: UUID(), at: date ?? clock.now)
        game.grantLevelRewards(at: date ?? clock.now)
    }
}
