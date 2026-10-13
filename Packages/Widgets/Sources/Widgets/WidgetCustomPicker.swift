import Foundation

/// Розгорнутий вибір «Інше» у віджеті (рішення від 09.10.2026, SPEC-WIDGETS §4.3).
///
/// Вікна поверх робочого столу віджет показати не може, а дія з кнопки нічого не може спитати. Тож «Інше» лише
/// розгортає у віджеті підказки зі шторки «Інше». Це стан самого віджета, не даних: його пише розширення (звичайний
/// `AppIntent`, без запуску застосунку — тому швидко), читає таймлайн. Окремо для кожного віджета: розгорнутий
/// «Огляд дня» не має розгортати «Швидке додавання». Сам згортається за хвилину — щоб назавтра не зустріти підказки.
public struct WidgetCustomPicker: @unchecked Sendable {
    public static let window: TimeInterval = 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Спільні налаштування App Group — їх бачать і розширення, і застосунок (порція з підказки згортає вибір).
    public static var shared: WidgetCustomPicker {
        WidgetCustomPicker(defaults: UserDefaults(suiteName: WidgetSnapshotStore.appGroup) ?? .standard)
    }

    public func open(_ kind: WidgetKind, at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.key(kind))
    }

    public func close(_ kind: WidgetKind) {
        defaults.removeObject(forKey: Self.key(kind))
    }

    public func closeAll() {
        for kind in WidgetKind.allCases { close(kind) }
    }

    /// Коли вибір згорнеться сам; `nil` — згорнутий.
    public func closesAt(_ kind: WidgetKind, now: Date) -> Date? {
        let opened = defaults.double(forKey: Self.key(kind))
        guard opened > 0 else { return nil }
        let closes = Date(timeIntervalSince1970: opened).addingTimeInterval(Self.window)
        return closes > now ? closes : nil
    }

    public func isOpen(_ kind: WidgetKind, at date: Date) -> Bool {
        closesAt(kind, now: date).map { date < $0 } ?? false
    }

    private static func key(_ kind: WidgetKind) -> String { "widget.customPicker.\(kind.rawValue)" }
}
