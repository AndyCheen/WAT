import Foundation

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

public enum NotificationSoundSpec: Sendable, Equatable {
    case none
    case systemDefault
    case named(String)
}

/// Запит у центр сповіщень простими значеннями — без `UserNotifications`, щоб планування й
/// дифф тестувались у SPM-тестах, де `UNUserNotificationCenter.current()` падає (немає бандла).
public struct ScheduledRequest: Sendable, Equatable {
    public enum Trigger: Sendable, Equatable {
        /// Календарний момент. `floating` — компоненти без поясу: тригер іде за поясом пристрою.
        case calendar(DateComponents, floating: Bool)
        /// Одразу — відлуння розблокування (§12.1).
        case immediate
    }

    public var identifier: String
    public var title: String
    public var body: String
    public var categoryId: String?
    public var sound: NotificationSoundSpec
    public var interruption: NotificationInterruption
    public var trigger: Trigger
    /// Момент спрацювання — для in-memory центру й DEBUG-екрана.
    public var fireAt: Date?
    public var userInfo: [String: String]
    /// Відбиток змісту: однаковий план не переписує запит у центрі (§16.2, п. 4).
    public var fingerprint: String

    public init(identifier: String, title: String, body: String, categoryId: String?, sound: NotificationSoundSpec,
                interruption: NotificationInterruption = .active,
                trigger: Trigger, fireAt: Date?, userInfo: [String: String], fingerprint: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.categoryId = categoryId
        self.sound = sound
        self.interruption = interruption
        self.trigger = trigger
        self.fireAt = fireAt
        self.userInfo = userInfo
        self.fingerprint = fingerprint
    }
}

/// Те, що вже чекає доставки, — для диффу.
public struct PendingRequest: Sendable, Equatable {
    public var identifier: String
    public var fingerprint: String

    public init(identifier: String, fingerprint: String) {
        self.identifier = identifier
        self.fingerprint = fingerprint
    }
}

public struct NotificationActionSpec: Sendable, Equatable {
    public var id: String
    public var title: String
    public var opensApp: Bool
    public var destructive: Bool

    public init(id: String, title: String, opensApp: Bool = false, destructive: Bool = false) {
        self.id = id
        self.title = title
        self.opensApp = opensApp
        self.destructive = destructive
    }
}

public struct NotificationCategorySpec: Sendable, Equatable {
    public var id: String
    public var actions: [NotificationActionSpec]

    public init(id: String, actions: [NotificationActionSpec]) {
        self.id = id
        self.actions = actions
    }
}

/// `UNUserNotificationCenter`, закритий протоколом: у тестах і e2e його заміняє
/// `InMemoryNotificationCenter` (§16.10).
@MainActor
public protocol NotificationCenterProtocol: AnyObject {
    func authorization() async -> NotificationAuthorization
    /// Системний запит `[.alert, .sound]`. `.provisional` свідомо не використовується (§16.5).
    func requestAuthorization() async -> Bool
    func pendingRequests() async -> [PendingRequest]
    func add(_ request: ScheduledRequest) async
    func removePending(identifiers: [String])
    func removeDelivered(identifiers: [String])
    func setCategories(_ categories: [NotificationCategorySpec])
}

/// Відповідь користувача на сповіщення — `Sendable`-знімок `UNNotificationResponse`.
/// Делегат центру знімає його поза головним потоком і передає на `@MainActor` (§16.4).
public struct NotificationResponseInfo: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// Тап по самому сповіщенню.
        case open
        case dismiss
        case addGlass
        case otherAmount
        case snooze
        case pause
    }

    public var identifier: String
    public var action: Action
    public var userInfo: [String: String]

    public init(identifier: String, action: Action, userInfo: [String: String] = [:]) {
        self.identifier = identifier
        self.action = action
        self.userInfo = userInfo
    }

    /// Ідентифікатор дії з `UNNotificationResponse.actionIdentifier`.
    public init(identifier: String, actionIdentifier: String, userInfo: [String: String]) {
        let action: Action
        switch actionIdentifier {
        case NotificationActionID.addGlass: action = .addGlass
        case NotificationActionID.otherAmount: action = .otherAmount
        case NotificationActionID.snooze: action = .snooze
        case NotificationActionID.pause: action = .pause
        case "com.apple.UNNotificationDismissActionIdentifier": action = .dismiss
        default: action = .open
        }
        self.init(identifier: identifier, action: action, userInfo: userInfo)
    }

    public var route: NotificationTapRoute { NotificationTapRoute(encoded: userInfo[UserInfoKey.route] ?? "home") }
    /// Об'єм «+склянки» — той, що був у сповіщенні, а не поточне налаштування: назва дії
    /// прив'язана до категорії, і людина тиснула саме цю кнопку.
    public var glassMl: Int? { userInfo[UserInfoKey.glassMl].flatMap(Int.init) }
    public var portionMl: Int? { userInfo[UserInfoKey.portionMl].flatMap(Int.init) }
}

/// Ключі `userInfo` запиту.
public enum UserInfoKey {
    public static let type = "type"
    public static let slot = "slot"
    public static let day = "day"
    public static let route = "route"
    public static let glassMl = "glassMl"
    public static let portionMl = "portionMl"
    public static let fingerprint = "fp"
}
