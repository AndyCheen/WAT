import Foundation
import Core
import Persistence

/// Ядро збору статистики: запис подій, оновлення агрегатів, шина підписників,
/// відкат за `sourceRef` і повна перебудова лічильників з подій.
@MainActor
public final class MetricsService {
    private let store: MetricStoreProtocol
    private let calendar: CalendarService
    private var subscribers: [WeakSubscriber] = []

    public init(store: MetricStoreProtocol, calendar: CalendarService) {
        self.store = store
        self.calendar = calendar
    }

    // MARK: - Підписники

    private struct WeakSubscriber {
        weak var value: (any MetricsSubscriber)?
    }

    public func subscribe(_ subscriber: any MetricsSubscriber) {
        subscribers.append(WeakSubscriber(value: subscriber))
    }

    private func notifyRecord(_ event: RecordedMetricEvent) {
        subscribers = subscribers.filter { $0.value != nil }
        for wrapper in subscribers {
            wrapper.value?.metricsDidRecord(event, service: self)
        }
    }

    private func notifyRevert(_ events: [RecordedMetricEvent], sourceRef: UUID) {
        subscribers = subscribers.filter { $0.value != nil }
        for wrapper in subscribers {
            wrapper.value?.metricsDidRevert(events, sourceRef: sourceRef, service: self)
        }
    }

    // MARK: - Запис

    /// Записує подію, оновлює лічильники всіх періодів і сповіщає підписників.
    ///
    /// Ідемпотентність: подія з тим самим `name` + `sourceRef`, яка ще не відкочена,
    /// повторно не зараховується.
    @discardableResult
    public func record(_ event: MetricEvent) -> RecordedMetricEvent? {
        if let ref = event.sourceRef, isDuplicate(name: event.name, sourceRef: ref) {
            return nil
        }

        let dayKey = calendar.dayKey(for: event.occurredAt)
        let hour = calendar.hour(of: event.occurredAt)
        let record = MetricEventRecord(
            name: event.name.rawValue,
            occurredAt: event.occurredAt,
            dayKey: dayKey.rawValue,
            hourBucket: hour,
            value: event.value,
            payload: Self.encode(event.payload),
            sourceRef: event.sourceRef
        )
        store.insertEvent(record)
        applyToCounters(name: event.name, value: event.value, at: event.occurredAt, sign: 1)

        let recorded = RecordedMetricEvent(
            id: record.id,
            name: event.name,
            value: event.value,
            occurredAt: event.occurredAt,
            dayKey: dayKey.rawValue,
            hourBucket: hour,
            sourceRef: event.sourceRef,
            payload: event.payload
        )
        notifyRecord(recorded)
        return recorded
    }

    /// Відкат усіх подій, породжених однією дією (напр. видалення порції).
    @discardableResult
    public func revert(sourceRef: UUID, at date: Date) -> [RecordedMetricEvent] {
        let records = store.events(sourceRef: sourceRef).filter { $0.revertedAt == nil }
        guard !records.isEmpty else { return [] }

        var reverted: [RecordedMetricEvent] = []
        for record in records {
            record.revertedAt = date
            applyToCounters(
                name: MetricKey(rawValue: record.name),
                value: record.value,
                at: record.occurredAt,
                sign: -1
            )
            reverted.append(
                RecordedMetricEvent(
                    id: record.id,
                    name: MetricKey(rawValue: record.name),
                    value: record.value,
                    occurredAt: record.occurredAt,
                    dayKey: record.dayKey,
                    hourBucket: record.hourBucket,
                    sourceRef: record.sourceRef,
                    payload: Self.decode(record.payload)
                )
            )
        }
        notifyRevert(reverted, sourceRef: sourceRef)
        return reverted
    }

    /// Фіксація транзакції. Запис подій не зберігає контекст на кожен виклик —
    /// одна дія користувача породжує кілька подій, тож зберігаємось один раз на межі дії.
    public func commit() {
        store.save()
    }

    // MARK: - Читання

    public func sum(_ key: MetricKey, periodType: MetricPeriodType = .day, periodKey: String) -> Double {
        store.counter(metricKey: key.rawValue, periodType: periodType, periodKey: periodKey)?.sum ?? 0
    }

    public func count(_ key: MetricKey, periodType: MetricPeriodType = .day, periodKey: String) -> Int {
        store.counter(metricKey: key.rawValue, periodType: periodType, periodKey: periodKey)?.count ?? 0
    }

    public func maxValue(_ key: MetricKey, periodType: MetricPeriodType = .all, periodKey: String = "all") -> Double {
        store.counter(metricKey: key.rawValue, periodType: periodType, periodKey: periodKey)?.maxValue ?? 0
    }

    public func sumToday(_ key: MetricKey) -> Double {
        sum(key, periodType: .day, periodKey: calendar.today.rawValue)
    }

    public func sumAllTime(_ key: MetricKey) -> Double {
        sum(key, periodType: .all, periodKey: Self.allTimeKey)
    }

    public func events(_ key: MetricKey? = nil, day: DayKey? = nil) -> [MetricEventRecord] {
        store.events(name: key?.rawValue, dayKey: day?.rawValue)
    }

    /// Ключі періодів для дати — використовується і при записі, і при читанні.
    public func periodKeys(for date: Date) -> [(MetricPeriodType, String)] {
        let day = calendar.dayKey(for: date)
        return [
            (.day, day.rawValue),
            (.week, calendar.weekKey(for: date).rawValue),
            (.month, calendar.monthKey(for: date).rawValue),
            (.year, String(day.year)),
            (.all, Self.allTimeKey)
        ]
    }

    public nonisolated static let allTimeKey = "all"

    // MARK: - Перебудова

    /// Повністю перебудовує лічильники з журналу подій.
    /// Використовується після міграцій і в тестах як перевірка узгодженості.
    public func rebuildCounters() {
        store.deleteAllCounters()
        for record in store.allEvents() where record.revertedAt == nil {
            applyToCounters(
                name: MetricKey(rawValue: record.name),
                value: record.value,
                at: record.occurredAt,
                sign: 1
            )
        }
        store.save()
    }

    // MARK: - Внутрішнє

    private func isDuplicate(name: MetricKey, sourceRef: UUID) -> Bool {
        store.events(sourceRef: sourceRef).contains {
            $0.name == name.rawValue && $0.revertedAt == nil
        }
    }

    private func applyToCounters(name: MetricKey, value: Double, at date: Date, sign: Double) {
        for (type, key) in periodKeys(for: date) {
            let counter = store.makeCounter(metricKey: name.rawValue, periodType: type, periodKey: key)
            counter.sum += value * sign
            counter.count += Int(sign)
            if sign > 0 {
                counter.maxValue = max(counter.maxValue, value)
                counter.minValue = counter.count == 1 ? value : min(counter.minValue, value)
            } else {
                // Мінімум і максимум не «відкочуються» арифметично — перечитуємо з подій.
                // Відкат трапляється рідко, тому ціна перерахунку прийнятна.
                recomputeExtremes(name: name, type: type, periodKey: key, counter: counter)
            }
            counter.lastUpdatedAt = date
        }
    }

    private func recomputeExtremes(
        name: MetricKey,
        type: MetricPeriodType,
        periodKey key: String,
        counter: MetricCounterRecord
    ) {
        let values = store.events(name: name.rawValue, dayKey: nil)
            .filter { record in
                periodKeys(for: record.occurredAt).contains { $0.0 == type && $0.1 == key }
            }
            .map(\.value)
        counter.maxValue = values.max() ?? 0
        counter.minValue = values.min() ?? 0
    }

    private static func encode(_ payload: [String: String]) -> Data? {
        payload.isEmpty ? nil : try? JSONEncoder().encode(payload)
    }

    private static func decode(_ data: Data?) -> [String: String] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
