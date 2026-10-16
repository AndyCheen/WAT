import Foundation

/// Бал «Рівномірності за день» 0…100 — одна формула для графіка 4a (`Insights`) і досягнень
/// «Рівна» й «Ідеальна крива» (`Gamification`, WAT-24): пакети одне одного не імпортують, а дві
/// копії формули розійшлися б при першій правці.
public enum Evenness {
    /// Рахуємо відстань фактичного розподілу по частинах доби від цільового: `score = 100 × (1 −
    /// ½·Σ|факт − ціль|)`. Цільові частки — з кривої темпу дня (`PaceCurve.partShares`), а не
    /// фіксовані 20/20/30/22/8 %: ніч поза активними годинами має частку 0, і вода там знижує бал
    /// (§13.6), а обрізаний підйомом ранок не вимагає повних 20 % (WAT-39).
    /// 100 — розподіл точно за кривою, 0 — уся вода в частині, де її не чекали.
    public static func score(partTotals: [Int], shares: [Double]) -> Int {
        let total = partTotals.reduce(0, +)
        guard total > 0 else { return 0 }
        let distance = DayPart.allCases.reduce(0.0) { sum, part in
            let actual = Double(partTotals[part.rawValue]) / Double(total)
            return sum + abs(actual - shares[part.rawValue])
        }
        return Int(((1 - distance / 2) * 100).rounded())
    }
}
