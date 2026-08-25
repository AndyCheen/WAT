import Foundation
import SwiftData

/// Сира подія статистики. Джерело правди, з якого перебудовуються всі агрегати.
@Model
public final class MetricEventRecord {
    public var id: UUID = UUID()
    public var name: String = ""
    public var occurredAt: Date = Date()
    public var dayKey: String = ""
    public var hourBucket: Int = 0
    public var value: Double = 0
    public var payload: Data?
    /// Посилання на сутність-джерело (напр. `Intake.id`) — робить можливим відкат.
    public var sourceRef: UUID?
    public var revertedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        occurredAt: Date,
        dayKey: String,
        hourBucket: Int,
        value: Double,
        payload: Data? = nil,
        sourceRef: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.occurredAt = occurredAt
        self.dayKey = dayKey
        self.hourBucket = hourBucket
        self.value = value
        self.payload = payload
        self.sourceRef = sourceRef
    }
}

/// Згорнутий агрегат по метриці за період — швидкі перевірки умов завдань і досягнень.
@Model
public final class MetricCounterRecord {
    public var metricKey: String = ""
    public var periodTypeRaw: Int = MetricPeriodType.day.rawValue
    public var periodKey: String = ""
    public var sum: Double = 0
    public var count: Int = 0
    public var minValue: Double = 0
    public var maxValue: Double = 0
    public var lastUpdatedAt: Date = Date()

    public init(metricKey: String, periodType: MetricPeriodType, periodKey: String) {
        self.metricKey = metricKey
        self.periodTypeRaw = periodType.rawValue
        self.periodKey = periodKey
    }

    public var periodType: MetricPeriodType { MetricPeriodType(rawValue: periodTypeRaw) ?? .day }
    public var average: Double { count > 0 ? sum / Double(count) : 0 }
}
