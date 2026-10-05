import Foundation
import SwiftData
import Core

/// Денний агрегат. Графіки та правила читають його, а не сирі порції.
@Model
public final class DayLog {
    @Attribute(.unique) public var dayKey: String = ""
    public var goalMlSnapshot: Int = 2000
    /// Підйом і відбій цього дня (WAT-39) — як `goalMlSnapshot`: оновлюються лише для поточного
    /// дня, тож зміна розкладу не переписує цілі частин доби, за які XP уже нараховано.
    /// `nil` — історія до WAT-39; для неї розклад береться з профілю.
    public var wakeMinutesSnapshot: Int?
    public var sleepMinutesSnapshot: Int?
    public var totalMl: Int = 0
    public var countedMl: Int = 0
    public var entriesCount: Int = 0
    public var firstIntakeAt: Date?
    public var lastIntakeAt: Date?
    public var timeZoneId: String = TimeZone.current.identifier
    public var closedAt: Date?
    /// Розподіл по частинах доби (5 значень у мл) — денормалізація заради швидких графіків.
    public var partTotals: [Int] = [0, 0, 0, 0, 0]

    @Relationship(deleteRule: .cascade, inverse: \Intake.dayLog)
    public var intakes: [Intake]? = []

    public init(dayKey: String, goalMlSnapshot: Int, timeZoneId: String = TimeZone.current.identifier) {
        self.dayKey = dayKey
        self.goalMlSnapshot = goalMlSnapshot
        self.timeZoneId = timeZoneId
    }

    /// Стеля обліку: понад 120 % норми вода більше не зараховується (ТЗ §4.3).
    public static let overflowFactor = 1.2

    public var capMl: Int { Int(Double(goalMlSnapshot) * Self.overflowFactor) }
    public var completionPct: Int {
        guard goalMlSnapshot > 0 else { return 0 }
        return Int((Double(countedMl) / Double(goalMlSnapshot) * 100).rounded())
    }
    public var goalMet: Bool { countedMl >= goalMlSnapshot }

    public var scheduleSnapshot: DaySchedule? {
        get {
            guard let wake = wakeMinutesSnapshot, let sleep = sleepMinutesSnapshot else { return nil }
            return DaySchedule(wakeMinutes: wake, sleepMinutes: sleep)
        }
        set {
            wakeMinutesSnapshot = newValue?.wakeMinutes
            sleepMinutesSnapshot = newValue?.sleepMinutes
        }
    }
    public var isCapped: Bool { totalMl > capMl }
}
