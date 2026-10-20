import Foundation
import SwiftData
import Core

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

    /// Найменша порція, яку можна набрати в системі: 50 мл або перша ціла унція в межах — 2 унц. = 59 мл (WAT-59).
    /// Степер в унціях на нижній межі дає ще й рівно 50 мл, і їх теж видно як «2 унц.».
    public static func smallestMl(in unit: VolumeUnit) -> Int {
        clamp(unit.milliliters(units: unit.unitsRoundedUp(minAmountMl)))
    }

    /// Усі об'єми, що людина бачить як найменшу порцію своєї системи, — {50, 59}.
    public static let smallestAmountsMl: Set<Int> = Set(VolumeUnit.allCases.map(smallestMl(in:)) + [minAmountMl])
}
