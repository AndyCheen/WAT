#if canImport(UserNotifications)
import Foundation
import UserNotifications

/// Справжній `UNUserNotificationCenter`. Створюється **лише** в застосунку: у процесі SPM-тестів
/// немає бандла, і `UNUserNotificationCenter.current()` там падає.
@MainActor
public final class SystemNotificationCenter: NotificationCenterProtocol {
    private let center: UNUserNotificationCenter

    public init() {
        center = UNUserNotificationCenter.current()
    }

    public func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func pendingRequests() async -> [PendingRequest] {
        await center.pendingNotificationRequests().map {
            PendingRequest(
                identifier: $0.identifier,
                fingerprint: $0.content.userInfo[UserInfoKey.fingerprint] as? String ?? ""
            )
        }
    }

    public func add(_ request: ScheduledRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        if let category = request.categoryId { content.categoryIdentifier = category }
        content.userInfo = request.userInfo
        // `timeSensitive` не використовується: вода — не термінова справа, і цей рівень
        // пробивав би Focus користувача (§13.2).
        content.interruptionLevel = request.interruption == .passive ? .passive : .active
        switch request.sound {
        case .none: content.sound = nil
        case .systemDefault: content.sound = .default
        case .named(let name): content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        }

        let trigger: UNNotificationTrigger?
        switch request.trigger {
        case .calendar(let components, _):
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .immediate:
            trigger = nil
        }
        let notification = UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        try? await center.add(notification)
    }

    public func removePending(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeDelivered(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func setCategories(_ categories: [NotificationCategorySpec]) {
        let mapped = categories.map { spec in
            UNNotificationCategory(
                identifier: spec.id,
                actions: spec.actions.map { action in
                    var options: UNNotificationActionOptions = []
                    if action.opensApp { options.insert(.foreground) }
                    if action.destructive { options.insert(.destructive) }
                    return UNNotificationAction(identifier: action.id, title: action.title, options: options)
                },
                intentIdentifiers: [],
                options: []
            )
        }
        center.setNotificationCategories(Set(mapped))
    }
}
#endif
