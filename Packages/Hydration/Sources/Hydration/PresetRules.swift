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

/// Кроки редагування об'єму в одиницях системи (WAT-46): людина крокує по тому, що бачить.
public enum VolumeSteps {
    /// Кнопки порцій: до 1 л — 50 мл, від 1 л — 100 мл («1.05 л» нікому не потрібне, а дорога до 2 л
    /// удвічі коротша); в унціях — 1 унц. до кварти (32 унц.), далі 2 унц..
    public static func preset(_ unit: VolumeUnit) -> VolumeGrid {
        unit.isMetric ? VolumeGrid(fine: 50, coarse: 100, coarseFrom: 1000) : VolumeGrid(fine: 1, coarse: 2, coarseFrom: 32)
    }

    /// Шторка «Інше».
    public static func custom(_ unit: VolumeUnit) -> VolumeGrid {
        VolumeGrid(step: unit.isMetric ? 50 : 1)
    }

    /// Денна мета: 250 мл або чашка 8 унц..
    public static func goal(_ unit: VolumeUnit) -> VolumeGrid {
        VolumeGrid(step: unit.isMetric ? 250 : 8)
    }

    /// «Моя склянка» і вікно «Склянка».
    public static func glass(_ unit: VolumeUnit) -> VolumeGrid {
        VolumeGrid(step: unit.isMetric ? 25 : 1)
    }
}
