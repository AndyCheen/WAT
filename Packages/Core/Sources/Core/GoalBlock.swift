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
///
/// Порції поза активними годинами не губляться: до підйому — у першому блоці, після відбою —
/// в останньому (рішення від 05.10.2026, WAT-39). Хто почав пити о 06:30 при підйомі о 08:00,
/// той пив уранці, і ранкову ціль закрито, хоча графік каже інакше.
public struct GoalBlock: Sendable, Equatable {
    public let parts: [DayPart]
    /// Межі за розкладом — від них рахується ціль і дедлайн чекпоінта.
    public let fromMinute: Int
    public let toMinute: Int
    /// `E(кінець) − E(початок)` в округлених значеннях — цілі блоків складаються точно в норму.
    public let targetMl: Int
    /// Межі зарахування порцій: у першого блоку від 00:00, в останнього — до 24:00.
    let countsFromMinute: Int
    let countsToMinute: Int

    init(parts: [DayPart], fromMinute: Int, toMinute: Int, targetMl: Int, opensDay: Bool, closesDay: Bool) {
        self.parts = parts
        self.fromMinute = fromMinute
        self.toMinute = toMinute
        self.targetMl = targetMl
        countsFromMinute = opensDay ? 0 : fromMinute
        countsToMinute = closesDay ? 24 * 60 : toMinute
    }

    /// Частина, якою блок закінчується: її кінець — дедлайн чекпоінта, її назва — у тексті.
    public var deadlinePart: DayPart { parts[parts.count - 1] }

    /// Чи зараховується блоку порція цієї хвилини — з урахуванням країв дня.
    public func contains(minute: Int) -> Bool { minute >= countsFromMinute && minute < countsToMinute }

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
        return blocks.enumerated().map { index, block in
            GoalBlock(parts: block.parts, fromMinute: block.from, toMinute: block.to,
                      targetMl: roundedTarget(fromMinute: block.from, toMinute: block.to),
                      opensDay: index == 0, closesDay: index == blocks.count - 1)
        }
    }

    /// Блок, якому зараховується порція цієї хвилини: до підйому — перший, після відбою —
    /// останній. `nil` лише тоді, коли блоків немає зовсім (нульові активні години).
    public func goalBlock(containing minute: Int) -> GoalBlock? {
        goalBlocks().first { $0.contains(minute: minute) }
    }
}

/// Поточна частина доби для рядка на головному (WAT-40): яка частина, скільки в ній випито
/// і скільки хвилин до її кінця. Ті самі блоки й те саме «випито», що в чекпоінта, XP і звіту.
public struct DayPartProgress: Sendable, Equatable {
    public let block: GoalBlock
    public let drunkMl: Int
    public let minutesLeft: Int

    /// Скільки бракує до цілі — точно, без округлення: як показати, вирішує екран.
    public var leftMl: Int { max(0, block.targetMl - drunkMl) }
    public var isReached: Bool { drunkMl >= block.targetMl }
    public var fraction: Double { block.targetMl > 0 ? min(1, Double(drunkMl) / Double(block.targetMl)) : 1 }
}

extension PaceCurve {
    /// Частина доби, що триває о хвилині `minute`. `nil` до підйому й після відбою: частина ще
    /// не почалась або вже скінчилась (рішення від 05.10.2026, WAT-40). Порція до підйому все одно
    /// рахується першому блоку — як у XP, — тож о підйомі рядок уже бачить ранкову склянку.
    public func dayPartProgress(atMinute minute: Int, portions: [TimedPortion]) -> DayPartProgress? {
        guard let block = goalBlocks().first(where: { minute >= $0.fromMinute && minute < $0.toMinute }) else {
            return nil
        }
        return DayPartProgress(block: block, drunkMl: block.drunkMl(of: portions), minutesLeft: block.toMinute - minute)
    }
}
