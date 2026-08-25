import Foundation

/// Подія статистики у вигляді, в якому її публікують модулі.
public struct MetricEvent: Sendable {
    public let name: MetricKey
    public let value: Double
    public let occurredAt: Date
    /// Ідентифікатор сутності-джерела. Дає ідемпотентність і можливість відкату.
    public let sourceRef: UUID?
    public let payload: [String: String]

    public init(
        name: MetricKey,
        value: Double = 1,
        occurredAt: Date,
        sourceRef: UUID? = nil,
        payload: [String: String] = [:]
    ) {
        self.name = name
        self.value = value
        self.occurredAt = occurredAt
        self.sourceRef = sourceRef
        self.payload = payload
    }
}

/// Подія, вже записана в сховище — саме її бачать підписники.
public struct RecordedMetricEvent: Sendable {
    public let id: UUID
    public let name: MetricKey
    public let value: Double
    public let occurredAt: Date
    public let dayKey: String
    public let hourBucket: Int
    public let sourceRef: UUID?
    public let payload: [String: String]
}

/// Підписник шини. Модулі XP, квестів, досягнень реалізують саме цей протокол
/// і нічого не знають один про одного.
@MainActor
public protocol MetricsSubscriber: AnyObject {
    func metricsDidRecord(_ event: RecordedMetricEvent, service: MetricsService)
    func metricsDidRevert(_ events: [RecordedMetricEvent], sourceRef: UUID, service: MetricsService)
}

public extension MetricsSubscriber {
    func metricsDidRevert(_ events: [RecordedMetricEvent], sourceRef: UUID, service: MetricsService) {}
}
