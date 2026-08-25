import Foundation
import Core

/// Чисті обчислення без БД — саме вони покриті unit-тестами.
public enum InsightsCalculators {

    // MARK: - Рівномірність

    /// Бал рівномірності 0…100.
    ///
    /// Рахуємо відстань фактичного розподілу по частинах доби від ідеального
    /// (`DayPart.idealShare`): `score = 100 × (1 − ½·Σ|факт − ідеал|)`.
    /// 100 — розподіл точно за планом, 0 — уся вода в одній «неправильній» частині доби.
    public static func evennessScore(partTotals: [Int]) -> Int {
        let total = partTotals.reduce(0, +)
        guard total > 0 else { return 0 }
        let distance = DayPart.allCases.reduce(0.0) { sum, part in
            let actual = Double(partTotals[part.rawValue]) / Double(total)
            return sum + abs(actual - part.idealShare)
        }
        return Int(((1 - distance / 2) * 100).rounded())
    }

    public static func evennessRows(partTotals: [Int], goalMl: Int) -> [EvennessRow] {
        let ideals = DayPart.allCases.map { Int((Double(goalMl) * $0.idealShare).rounded()) }
        let maxValue = max(partTotals.max() ?? 0, ideals.max() ?? 0, 1)
        return DayPart.allCases.map { part in
            EvennessRow(
                part: part,
                ml: partTotals[part.rawValue],
                idealMl: ideals[part.rawValue],
                fraction: Double(partTotals[part.rawValue]) / Double(maxValue),
                tickFraction: Double(ideals[part.rawValue]) / Double(maxValue)
            )
        }
    }

    // MARK: - Типова доба

    /// Медіана й міжквартильний розкид часток по частинах доби за кілька днів.
    /// Дні без води ігноруються — інакше медіана «прилипає» до нуля.
    public static func typicalDay(dailyPartTotals: [[Int]]) -> TypicalDayReport {
        let days = dailyPartTotals.filter { $0.reduce(0, +) > 0 }
        guard !days.isEmpty else { return .empty }

        let rows = DayPart.allCases.map { part -> TypicalDayRow in
            let shares = days.map { totals -> Double in
                let sum = Double(totals.reduce(0, +))
                return sum > 0 ? Double(totals[part.rawValue]) / sum : 0
            }.sorted()

            return TypicalDayRow(
                part: part,
                median: percentile(shares, 0.5),
                low: percentile(shares, 0.25),
                high: percentile(shares, 0.75),
                ideal: part.idealShare
            )
        }
        return TypicalDayReport(rows: rows, daysCounted: days.count)
    }

    /// Лінійна інтерполяція перцентиля у відсортованому масиві.
    public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    // MARK: - Теплокарта

    /// Години-стовпці теплокарти: 9 бакетів по 2 години, як у макеті.
    public static let heatmapHours = [6, 8, 10, 12, 14, 16, 18, 20, 22]

    public static func heatmapLevel(ml: Int, maxMl: Int) -> Int {
        guard ml > 0, maxMl > 0 else { return 0 }
        let ratio = Double(ml) / Double(maxMl)
        switch ratio {
        case ..<0.25: return 1
        case ..<0.5: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }

    public static func bucketIndex(forHour hour: Int) -> Int? {
        guard hour >= heatmapHours[0] else { return nil }
        let index = (hour - heatmapHours[0]) / 2
        return index < heatmapHours.count ? index : nil
    }
}
