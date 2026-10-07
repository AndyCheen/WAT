import Foundation
import Persistence

/// Правила кнопок порцій (WAT-45): крок степера й перше значення шторки «Інше».
public enum PresetRules {
    /// До 1 л крок 50 мл, від 1 л — 100 мл: «1.05 л» нікому не потрібне, а дорога до 2 л удвічі коротша.
    public static let fineStepMl = 50
    public static let coarseStepMl = 100
    public static let coarseFromMl = 1000
    /// Шторка «Інше», поки нею не користувались, — як було до WAT-45.
    public static let firstCustomAmountMl = 300

    /// Наступне значення на сітці: кратні 50 до 1 л, кратні 100 від 1 л. Значення поза сіткою
    /// (старе «1050») стає на найближчу вузлову точку в бік кроку, а не тягне зсув далі.
    public static func stepped(_ ml: Int, up: Bool) -> Int {
        let next: Int
        if up {
            let step = ml < coarseFromMl ? fineStepMl : coarseStepMl
            next = (ml / step + 1) * step
        } else {
            let step = ml <= coarseFromMl ? fineStepMl : coarseStepMl
            next = ((ml - 1) / step) * step
        }
        return Intake.clamp(next)
    }
}
