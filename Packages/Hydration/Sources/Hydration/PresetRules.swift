import Foundation
import Persistence

/// Правила кнопок порцій (WAT-45): крок степера й перше значення шторки «Інше».
public enum PresetRules {
    public static let stepMl = 50
    /// Шторка «Інше», поки нею не користувались, — як було до WAT-45.
    public static let firstCustomAmountMl = 300
}
