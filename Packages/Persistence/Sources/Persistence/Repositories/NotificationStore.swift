import Foundation
import SwiftData
import Core

@MainActor
public protocol NotificationStoreProtocol: AnyObject {
    func settings() -> NotificationSettings
    func quietPeriods() -> [QuietPeriod]
    @discardableResult
    func addQuietPeriod(fromMinutes: Int, toMinutes: Int, weekdayMask: Int) -> QuietPeriod
    func delete(_ period: QuietPeriod)
    func log(identifier: String) -> NotificationLog?
    /// Рядки журналу з `fireAt` у `[from, to)`, за зростанням часу.
    func logs(firingFrom from: Date, to: Date) -> [NotificationLog]
    func insert(_ log: NotificationLog)
    func deleteLogs(firedBefore date: Date)
    func save()
}

/// Налаштування, тихі періоди й журнал сповіщень.
///
/// Журнал кешується за ідентифікатором: перепланування на кожну дію перебирає всі рядки
/// горизонту, а `@Attribute(.unique)` у SwiftData при повторній вставці мовчки робить
/// upsert — тож рядок завжди спершу шукається тут, а не створюється навмання.
@MainActor
public final class NotificationStore: NotificationStoreProtocol {
    private let context: ModelContext
    private var cachedSettings: NotificationSettings?
    private var logCache: [String: NotificationLog]?

    public init(context: ModelContext) {
        self.context = context
    }

    public func settings() -> NotificationSettings {
        if let cachedSettings { return cachedSettings }
        let existing = (try? context.fetch(FetchDescriptor<NotificationSettings>()))?.first
        let settings = existing ?? NotificationSettings()
        if existing == nil {
            context.insert(settings)
            save()
        }
        cachedSettings = settings
        return settings
    }

    public func quietPeriods() -> [QuietPeriod] {
        let descriptor = FetchDescriptor<QuietPeriod>(sortBy: [SortDescriptor(\.order)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func addQuietPeriod(fromMinutes: Int, toMinutes: Int, weekdayMask: Int) -> QuietPeriod {
        let order = (quietPeriods().map(\.order).max() ?? -1) + 1
        let period = QuietPeriod(order: order, weekdayMask: weekdayMask, fromMinutes: fromMinutes, toMinutes: toMinutes)
        context.insert(period)
        save()
        return period
    }

    public func delete(_ period: QuietPeriod) {
        context.delete(period)
        save()
    }

    public func log(identifier: String) -> NotificationLog? {
        loadedLogs()[identifier]
    }

    public func logs(firingFrom from: Date, to: Date) -> [NotificationLog] {
        loadedLogs().values
            .filter { $0.fireAt >= from && $0.fireAt < to }
            .sorted { $0.fireAt < $1.fireAt }
    }

    public func insert(_ log: NotificationLog) {
        var cache = loadedLogs()
        if let existing = cache[log.identifier], existing !== log { context.delete(existing) }
        context.insert(log)
        cache[log.identifier] = log
        logCache = cache
    }

    public func deleteLogs(firedBefore date: Date) {
        var cache = loadedLogs()
        for (identifier, log) in cache where log.fireAt < date {
            context.delete(log)
            cache[identifier] = nil
        }
        logCache = cache
    }

    public func save() {
        do { try context.save() } catch { AppLog.persistence.error("save: \(error)") }
    }

    private func loadedLogs() -> [String: NotificationLog] {
        if let logCache { return logCache }
        let all = (try? context.fetch(FetchDescriptor<NotificationLog>())) ?? []
        let cache = Dictionary(all.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        logCache = cache
        return cache
    }
}
