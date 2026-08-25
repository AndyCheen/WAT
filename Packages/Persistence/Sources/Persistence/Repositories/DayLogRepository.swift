import Foundation
import SwiftData
import Core

@MainActor
public protocol DayLogRepositoryProtocol: AnyObject {
    func dayLog(for day: DayKey, goalMl: Int, timeZoneId: String) -> DayLog
    func existingDayLog(for day: DayKey) -> DayLog?
    func dayLogs(from: DayKey, to: DayKey) -> [DayLog]
    func dayLogs(in month: MonthKey) -> [DayLog]
    func allDayLogs() -> [DayLog]
    func earliestDayKey() -> DayKey?
    func activeIntakes(for day: DayKey) -> [Intake]
    func intake(id: UUID) -> Intake?
    func insert(_ intake: Intake, into log: DayLog)
    func save()
}

@MainActor
public final class DayLogRepository: DayLogRepositoryProtocol {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func dayLog(for day: DayKey, goalMl: Int, timeZoneId: String) -> DayLog {
        if let existing = existingDayLog(for: day) { return existing }
        let log = DayLog(dayKey: day.rawValue, goalMlSnapshot: goalMl, timeZoneId: timeZoneId)
        context.insert(log)
        save()
        return log
    }

    public func existingDayLog(for day: DayKey) -> DayLog? {
        let key = day.rawValue
        var descriptor = FetchDescriptor<DayLog>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func dayLogs(from: DayKey, to: DayKey) -> [DayLog] {
        let lower = from.rawValue, upper = to.rawValue
        let descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func dayLogs(in month: MonthKey) -> [DayLog] {
        let prefix = month.rawValue
        let lower = prefix + "-00", upper = prefix + "-99"
        let descriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func allDayLogs() -> [DayLog] {
        (try? context.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.dayKey)]))) ?? []
    }

    public func earliestDayKey() -> DayKey? {
        var descriptor = FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.dayKey)])
        descriptor.fetchLimit = 1
        guard let first = (try? context.fetch(descriptor))?.first else { return nil }
        return DayKey(rawValue: first.dayKey)
    }

    public func activeIntakes(for day: DayKey) -> [Intake] {
        guard let log = existingDayLog(for: day) else { return [] }
        return (log.intakes ?? [])
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func intake(id: UUID) -> Intake? {
        var descriptor = FetchDescriptor<Intake>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func insert(_ intake: Intake, into log: DayLog) {
        context.insert(intake)
        intake.dayLog = log
    }

    public func save() {
        do { try context.save() } catch { AppLog.persistence.error("save: \(error)") }
    }
}
