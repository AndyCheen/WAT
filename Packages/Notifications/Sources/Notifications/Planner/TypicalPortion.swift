import Foundation

/// Типова порція `P` — медіана порцій за 14 днів, обмежена 150…500 мл і округлена до 50
/// (SPEC-NOTIFICATIONS §3.3). Без історії дорівнює «моїй склянці».
///
/// Медіана, а не середнє: одна пляшка 1 л не повинна зсувати «звичайну» порцію.
public enum TypicalPortion {
    public static func compute(_ amounts: [Int], glassMl: Int, rules: NotificationRules = .default) -> Int {
        guard !amounts.isEmpty else { return glassMl }
        let sorted = amounts.sorted()
        let mid = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? Double(sorted[mid - 1] + sorted[mid]) / 2
            : Double(sorted[mid])
        let step = Double(rules.portionStep)
        let rounded = Int((median / step).rounded()) * rules.portionStep
        return min(rules.portionClamp.upperBound, max(rules.portionClamp.lowerBound, rounded))
    }
}
