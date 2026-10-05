import Foundation

/// Порція в межах доби: хвилина від 00:00 і об'єм. Без `Date`, як і `PaceCurve`.
public struct TimedPortion: Sendable, Equatable {
    public let minute: Int
    public let ml: Int

    public init(minute: Int, ml: Int) {
        self.minute = minute
        self.ml = ml
    }
}

/// Ціль частини доби (SPEC-NOTIFICATIONS §9): за неї приходить чекпоінт, нараховується XP
/// `dayPartGoal` і ставиться ✓ у денному звіті. Одне визначення на всіх, інакше «ранок» у
/// сповіщенні, у XP і в звіті означав би різні години.
///
/// Межі — ті самі `DayPart`, обрізані активними годинами. Частина, що після обрізання коротша
/// за `minSegmentMinutes`, зливається з наступною (остання — з попередньою): при 08:00–22:00
/// «ранок» 08–09 іде разом із «полуднем», і цілі виходять до 12:00, 12–17 і 17–22.
public struct GoalBlock: Sendable, Equatable {
    public let parts: [DayPart]
    public let fromMinute: Int
    public let toMinute: Int
    /// `E(кінець) − E(початок)`, округлено до мілілітра.
    public let targetMl: Int

    /// Частина, якою блок закінчується: її кінець — дедлайн чекпоінта, її назва — у тексті.
    public var deadlinePart: DayPart { parts[parts.count - 1] }

    public func contains(minute: Int) -> Bool { minute >= fromMinute && minute < toMinute }

    /// Скільки випито в межах блоку. Рахується за часом порцій, а не за `DayLog.partTotals`:
    /// ніч при підйомі до 05:00 і відбої після 22:00 дає два відрізки на обох кінцях доби, а в
    /// `partTotals` вона одним числом — порція о 23:00 зарахувалась би ранковому блоку.
    public func drunkMl(of portions: [TimedPortion]) -> Int {
        portions.reduce(0) { contains(minute: $1.minute) ? $0 + $1.ml : $0 }
    }

    public func isReached(by portions: [TimedPortion]) -> Bool {
        drunkMl(of: portions) >= targetMl
    }

    /// «ранок і полудень», «день» — для підписів у звіті.
    public var title: String {
        let names = parts.map { $0.title.lowercased() }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " і " + names[names.count - 1]
    }
}

extension PaceCurve {
    /// Мінімальна тривалість частини доби в межах активних годин (`minSegment`, §15.2).
    public static let minGoalBlockMinutes = 120

    /// Цілі частин доби за зростанням часу (§9).
    public func goalBlocks(minSegmentMinutes: Int = PaceCurve.minGoalBlockMinutes) -> [GoalBlock] {
        var blocks: [(parts: [DayPart], from: Int, to: Int)] = segments.map { ([$0.part], $0.fromMinute, $0.toMinute) }
        // Зливаємо найпершу коротку з сусідом, поки коротких не лишиться: злиття може
        // зробити сусіда достатньо довгим, тож один прохід не завжди дає остаточний результат.
        while blocks.count > 1,
              let index = blocks.firstIndex(where: { $0.to - $0.from < minSegmentMinutes }) {
            let other = index < blocks.count - 1 ? index + 1 : index - 1
            let (first, second) = (min(index, other), max(index, other))
            blocks[first] = (blocks[first].parts + blocks[second].parts, blocks[first].from, blocks[second].to)
            blocks.remove(at: second)
        }
        return blocks.map {
            GoalBlock(parts: $0.parts, fromMinute: $0.from, toMinute: $0.to,
                      targetMl: Int(target(fromMinute: Double($0.from), toMinute: Double($0.to)).rounded()))
        }
    }

    /// Блок, у межі якого потрапляє хвилина; `nil` поза активними годинами.
    public func goalBlock(containing minute: Int) -> GoalBlock? {
        goalBlocks().first { $0.contains(minute: minute) }
    }
}
