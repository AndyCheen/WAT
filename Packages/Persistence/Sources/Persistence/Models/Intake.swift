import Foundation
import SwiftData

/// Порція води. Не редагується (ТЗ §4.3) — лише додається й видаляється.
@Model
public final class Intake {
    public var id: UUID = UUID()
    public var amountMl: Int = 0
    public var createdAt: Date = Date()
    public var sourceRaw: Int = IntakeSource.app.rawValue
    public var deletedAt: Date?
    public var dayLog: DayLog?

    public init(id: UUID = UUID(), amountMl: Int, createdAt: Date, source: IntakeSource = .app) {
        self.id = id
        self.amountMl = amountMl
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
    }

    public var source: IntakeSource { IntakeSource(rawValue: sourceRaw) ?? .app }
    public var isDeleted: Bool { deletedAt != nil }

    /// Ліміти однієї порції (PLAN.md §12.5) — захист від нереалістичних об'ємів.
    public static let minAmountMl = 50
    public static let maxAmountMl = 2000

    public static func clamp(_ ml: Int) -> Int { min(maxAmountMl, max(minAmountMl, ml)) }
    public static func isValid(_ ml: Int) -> Bool { (minAmountMl...maxAmountMl).contains(ml) }
}
