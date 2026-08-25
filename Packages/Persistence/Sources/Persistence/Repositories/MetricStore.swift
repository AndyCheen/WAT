import Foundation
import SwiftData
import Core

/// Низькорівневий доступ до подій і лічильників. Логіка живе в пакеті `Metrics`.
@MainActor
public protocol MetricStoreProtocol: AnyObject {
    func insertEvent(_ event: MetricEventRecord)
    func events(name: String?, dayKey: String?) -> [MetricEventRecord]
    func events(sourceRef: UUID) -> [MetricEventRecord]
    func allEvents() -> [MetricEventRecord]
    func counter(metricKey: String, periodType: MetricPeriodType, periodKey: String) -> MetricCounterRecord?
    func makeCounter(metricKey: String, periodType: MetricPeriodType, periodKey: String) -> MetricCounterRecord
    func counters(metricKey: String, periodType: MetricPeriodType) -> [MetricCounterRecord]
    func deleteAllCounters()
    func save()
}

@MainActor
public final class MetricStore: MetricStoreProtocol {
    private let context: ModelContext
    /// Лічильники читаються десятки разів на одну дію (5 періодів × кілька метрик × правила),
    /// тому тримаємо їх у памʼяті — інакше кожне додавання порції коштує ~40 вибірок з БД.
    private var counterCache: [String: MetricCounterRecord] = [:]
    /// Події за `sourceRef` перевіряються на кожен запис (ідемпотентність) і при відкаті.
    private var eventsBySource: [UUID: [MetricEventRecord]] = [:]

    public init(context: ModelContext) {
        self.context = context
    }

    private static func cacheKey(_ metricKey: String, _ periodType: MetricPeriodType, _ periodKey: String) -> String {
        "\(metricKey)|\(periodType.rawValue)|\(periodKey)"
    }

    public func insertEvent(_ event: MetricEventRecord) {
        context.insert(event)
        if let ref = event.sourceRef {
            eventsBySource[ref, default: []].append(event)
        }
    }

    public func events(name: String?, dayKey: String?) -> [MetricEventRecord] {
        var descriptor = FetchDescriptor<MetricEventRecord>(sortBy: [SortDescriptor(\.occurredAt)])
        switch (name, dayKey) {
        case let (n?, d?):
            descriptor.predicate = #Predicate { $0.name == n && $0.dayKey == d && $0.revertedAt == nil }
        case let (n?, nil):
            descriptor.predicate = #Predicate { $0.name == n && $0.revertedAt == nil }
        case let (nil, d?):
            descriptor.predicate = #Predicate { $0.dayKey == d && $0.revertedAt == nil }
        case (nil, nil):
            descriptor.predicate = #Predicate { $0.revertedAt == nil }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    public func events(sourceRef: UUID) -> [MetricEventRecord] {
        if let cached = eventsBySource[sourceRef] { return cached }
        let descriptor = FetchDescriptor<MetricEventRecord>(
            predicate: #Predicate { $0.sourceRef == sourceRef }
        )
        let found = (try? context.fetch(descriptor)) ?? []
        eventsBySource[sourceRef] = found
        return found
    }

    public func allEvents() -> [MetricEventRecord] {
        let descriptor = FetchDescriptor<MetricEventRecord>(sortBy: [SortDescriptor(\.occurredAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func counter(metricKey: String, periodType: MetricPeriodType, periodKey: String) -> MetricCounterRecord? {
        let cacheKey = Self.cacheKey(metricKey, periodType, periodKey)
        if let cached = counterCache[cacheKey] { return cached }
        let raw = periodType.rawValue
        var descriptor = FetchDescriptor<MetricCounterRecord>(
            predicate: #Predicate {
                $0.metricKey == metricKey && $0.periodTypeRaw == raw && $0.periodKey == periodKey
            }
        )
        descriptor.fetchLimit = 1
        let found = (try? context.fetch(descriptor))?.first
        if let found { counterCache[cacheKey] = found }
        return found
    }

    public func makeCounter(metricKey: String, periodType: MetricPeriodType, periodKey: String) -> MetricCounterRecord {
        if let existing = counter(metricKey: metricKey, periodType: periodType, periodKey: periodKey) {
            return existing
        }
        let created = MetricCounterRecord(metricKey: metricKey, periodType: periodType, periodKey: periodKey)
        context.insert(created)
        counterCache[Self.cacheKey(metricKey, periodType, periodKey)] = created
        return created
    }

    public func counters(metricKey: String, periodType: MetricPeriodType) -> [MetricCounterRecord] {
        let raw = periodType.rawValue
        let descriptor = FetchDescriptor<MetricCounterRecord>(
            predicate: #Predicate { $0.metricKey == metricKey && $0.periodTypeRaw == raw },
            sortBy: [SortDescriptor(\.periodKey)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    public func deleteAllCounters() {
        counterCache.removeAll()
        eventsBySource.removeAll()
        // Видаляємо поштучно: `delete(model:)` не бачить ще не збережених обʼєктів,
        // а лічильники навмисно зберігаються лише на межі дії.
        for counter in (try? context.fetch(FetchDescriptor<MetricCounterRecord>())) ?? [] {
            context.delete(counter)
        }
        save()
    }

    public func save() {
        do { try context.save() } catch { AppLog.persistence.error("save: \(error)") }
    }
}
