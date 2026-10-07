import Foundation
import Persistence

/// Правила кнопок порцій (WAT-45): крок степера й перше значення шторки «Інше».
public enum PresetRules {
    public static let stepMl = 50
    /// Шторка «Інше», поки нею не користувались, — як було до WAT-45.
    public static let firstCustomAmountMl = 300

    /// Наступне вільне значення в бік `delta`. Зайняте сусідньою кнопкою перескакується: дубль на
    /// головному безглуздий, а дві кнопки «250» мали б і однаковий ідентифікатор. Вільного в межах
    /// `Intake` немає — значення лишається.
    public static func stepped(_ current: Int, by delta: Int, taken: Set<Int>) -> Int {
        guard delta != 0 else { return current }
        var next = current
        repeat {
            next += delta
            guard Intake.isValid(next) else { return current }
        } while taken.contains(next)
        return next
    }
}
