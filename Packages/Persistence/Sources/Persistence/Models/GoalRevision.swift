import Foundation
import SwiftData

/// Історія денної норми: статистика минулих днів рахується за нормою, що діяла тоді.
@Model
public final class GoalRevision {
    public var effectiveFromKey: String = ""
    public var goalMl: Int = 2000
    public var sourceRaw: Int = GoalSource.manual.rawValue
    public var inputsSnapshot: Data?
    public var createdAt: Date = Date()

    public init(effectiveFromKey: String, goalMl: Int, source: GoalSource, createdAt: Date = Date()) {
        self.effectiveFromKey = effectiveFromKey
        self.goalMl = goalMl
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
    }

    public var source: GoalSource { GoalSource(rawValue: sourceRaw) ?? .manual }

    /// Допустимий діапазон норми (PLAN.md §12.5).
    public static let minGoalMl = 500
    public static let maxGoalMl = 5000

    public static func clamp(_ ml: Int) -> Int { min(maxGoalMl, max(minGoalMl, ml)) }
}
