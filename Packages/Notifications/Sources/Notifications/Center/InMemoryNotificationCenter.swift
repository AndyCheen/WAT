import Foundation

/// Центр сповіщень у пам'яті — для unit-тестів і e2e: реальні сповіщення в симуляторі
/// нестабільні, а системний запит дозволу заважав би сценаріям (§16.11).
@MainActor
public final class InMemoryNotificationCenter: NotificationCenterProtocol {
    public var status: NotificationAuthorization
    /// Що станеться, коли застосунок попросить дозвіл.
    public var grantsOnRequest: Bool
    public private(set) var requests: [String: ScheduledRequest] = [:]
    public private(set) var categories: [NotificationCategorySpec] = []
    public private(set) var removedDelivered: [String] = []
    public private(set) var authorizationRequests = 0
    public private(set) var addCount = 0

    public init(status: NotificationAuthorization = .authorized, grantsOnRequest: Bool = true) {
        self.status = status
        self.grantsOnRequest = grantsOnRequest
    }

    public func authorization() async -> NotificationAuthorization { status }

    public func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        guard status == .notDetermined else { return status == .authorized }
        status = grantsOnRequest ? .authorized : .denied
        return grantsOnRequest
    }

    public func pendingRequests() async -> [PendingRequest] {
        requests.values.map { PendingRequest(identifier: $0.identifier, fingerprint: $0.fingerprint) }
    }

    public func add(_ request: ScheduledRequest) async {
        addCount += 1
        requests[request.identifier] = request
    }

    public func removePending(identifiers: [String]) {
        for identifier in identifiers { requests[identifier] = nil }
    }

    public func removeDelivered(identifiers: [String]) {
        removedDelivered += identifiers
    }

    public func setCategories(_ categories: [NotificationCategorySpec]) {
        self.categories = categories
    }

    /// Заплановане за часом — для тестів і DEBUG.
    public var scheduled: [ScheduledRequest] {
        requests.values.sorted { ($0.fireAt ?? .distantPast) < ($1.fireAt ?? .distantPast) }
    }
}
