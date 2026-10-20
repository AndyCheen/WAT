import Foundation
import Core
import Persistence

/// Правила кнопок порцій (WAT-45): крок степера й перше значення шторки «Інше».
public enum PresetRules {
    /// Шторка «Інше», поки нею не користувались, — як було до WAT-45.
    public static let firstCustomAmountMl = 300

    /// Наступне значення кнопки порції на сітці системи (`VolumeSteps.preset`), у межах `Intake`.
    public static func stepped(_ ml: Int, up: Bool, unit: VolumeUnit = .milliliters) -> Int {
        Intake.clamp(unit.stepped(ml, up: up, grid: VolumeSteps.preset(unit)))
    }
}
