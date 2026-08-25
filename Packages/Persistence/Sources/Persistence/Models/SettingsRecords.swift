import Foundation
import SwiftData

/// Кнопки швидкого додавання на головному екрані (ТЗ §4.1 — редаговані).
@Model
public final class QuickAddPreset {
    public var id: UUID = UUID()
    public var order: Int = 0
    public var amountMl: Int = 200
    public var enabled: Bool = true

    public init(id: UUID = UUID(), order: Int, amountMl: Int, enabled: Bool = true) {
        self.id = id
        self.order = order
        self.amountMl = amountMl
        self.enabled = enabled
    }

    public static let defaults: [(order: Int, amountMl: Int)] = [(0, 200), (1, 500), (2, 1000)]
}

/// Правила сповіщень. Структура закладена наперед — UI зʼявиться на етапі «Сповіщення».
@Model
public final class NotificationRule {
    public var id: UUID = UUID()
    public var kindRaw: Int = NotificationKind.smart.rawValue
    public var enabled: Bool = true
    public var weekdayMask: Int = 0b1111111
    public var fromHour: Int = 8
    public var toHour: Int = 22
    public var quietRanges: Data?

    public init(id: UUID = UUID(), kind: NotificationKind, enabled: Bool = true) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.enabled = enabled
    }

    public var kind: NotificationKind { NotificationKind(rawValue: kindRaw) ?? .smart }
}
