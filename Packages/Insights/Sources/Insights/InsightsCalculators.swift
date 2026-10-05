import Foundation
import Core

/// Чисті обчислення без БД — саме вони покриті unit-тестами.
public enum InsightsCalculators {

    // MARK: - Рівномірність

    /// Бал рівномірності 0…100.
    ///
    /// Рахуємо відстань фактичного розподілу по частинах доби від цільового: `score = 100 × (1 −
    /// ½·Σ|факт − ціль|)`. Цільові частки — з кривої темпу дня (`PaceCurve.partShares`), а не
    /// фіксовані 20/20/30/22/8 %: ніч поза активними годинами має частку 0, і вода там знижує бал
    /// (§13.6), а обрізаний підйомом ранок не вимагає повних 20 % (WAT-39).
    /// 100 — розподіл точно за кривою, 0 — уся вода в частині, де її не чекали.
    public static func evennessScore(partTotals: [Int], shares: [Double]) -> Int {
        let total = partTotals.reduce(0, +)
        guard total > 0 else { return 0 }
        let distance = DayPart.allCases.reduce(0.0) { sum, part in
            let actual = Double(partTotals[part.rawValue]) / Double(total)
            return sum + abs(actual - shares[part.rawValue])
        }
        return Int(((1 - distance / 2) * 100).rounded())
    }

    /// `targetsMl` — `PaceCurve.partTargetsMl()`: ті самі мілілітри, що в цілях частин доби звіту.
    public static func evennessRows(partTotals: [Int], targetsMl: [Int]) -> [EvennessRow] {
        let maxValue = max(partTotals.max() ?? 0, targetsMl.max() ?? 0, 1)
        return DayPart.allCases.map { part in
            let target = targetsMl[part.rawValue]
            return EvennessRow(
                part: part,
                ml: partTotals[part.rawValue],
                idealMl: target,
                fraction: Double(partTotals[part.rawValue]) / Double(maxValue),
                tickFraction: target > 0 ? Double(target) / Double(maxValue) : nil
            )
        }
    }

    // MARK: - Типова доба

    /// Один день для «Типової доби»: випите по частинах і цільові частки з кривої цього дня.
    public struct DayParts: Equatable, Sendable {
        public let partTotals: [Int]
        public let shares: [Double]

        public init(partTotals: [Int], shares: [Double]) {
            self.partTotals = partTotals
            self.shares = shares
        }
    }

    /// Медіана й міжквартильний розкид часток по частинах доби за кілька днів.
    /// Дні без води ігноруються — інакше медіана «прилипає» до нуля.
    ///
    /// Ціль — середня частка з кривих урахованих днів: у будні й вихідні розклад може бути різний,
    /// і ризка лягає туди, куди в середньому вела крива. Нуль (ніч поза активними годинами) — без ризки.
    public static func typicalDay(days input: [DayParts]) -> TypicalDayReport {
        let days = input.filter { $0.partTotals.reduce(0, +) > 0 }
        guard !days.isEmpty else { return .empty }

        let rows = DayPart.allCases.map { part -> TypicalDayRow in
            let shares = days.map { day -> Double in
                let sum = Double(day.partTotals.reduce(0, +))
                return sum > 0 ? Double(day.partTotals[part.rawValue]) / sum : 0
            }.sorted()
            let ideal = days.reduce(0.0) { $0 + $1.shares[part.rawValue] } / Double(days.count)

            return TypicalDayRow(
                part: part,
                median: percentile(shares, 0.5),
                low: percentile(shares, 0.25),
                high: percentile(shares, 0.75),
                ideal: ideal > 0 ? ideal : nil
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
