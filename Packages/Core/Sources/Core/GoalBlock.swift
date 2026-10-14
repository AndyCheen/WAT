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
/// Блоків завжди три — ранок до 12:00, день 12–17, вечір від 17:00 (рішення від 13.10.2026, WAT-48,
/// §32), межі обрізані активними годинами. Раніше блоком була кожна з 5 `DayPart`, і від розкладу
/// залежало, скільки їх: 4 при підйомі о 06:00, 5 при 06:00–24:00, а відбій о 24:00 давав «ніч 22–24»
/// з ціллю 29 мл, закриту одним ковтком. Блок, коротший за `minSegmentMinutes` (підйом після 10:00,
/// відбій до 19:00), зливається з сусідом — нічні графіки мають два блоки.
///
/// Порції поза активними годинами не губляться: до підйому — у першому блоці, після відбою —
/// в останньому (рішення від 05.10.2026, WAT-39). Хто почав пити о 06:30 при підйомі о 08:00,
/// той пив уранці, і ранкову ціль закрито, хоча графік каже інакше.
public struct GoalBlock: Sendable, Equatable {
    public enum Kind: Int, CaseIterable, Sendable {
        case morning, day, evening

        /// Межі ранку й дня (12:00) і дня й вечора (17:00) — це межі `DayPart`, тож частина доби
        /// завжди цілком в одному блоці, і групувати можна відрізками. Лишається розвести ніч.
        static let dayStartMinute = 12 * 60

        public var title: String {
            switch self {
            case .morning: return "Ранок"
            case .day: return "День"
            case .evening: return "Вечір"
            }
        }

        /// Ключ у `refId` XP, id чекпоінта й медіанах звіту. Це ключі частин, якими блоки закінчувались
        /// при типовому 08:00–22:00 до WAT-48: так XP за вже закритий сьогодні блок не видається вдруге
        /// після оновлення, а заплановані чекпоінти зберігають id. Не залежить від розкладу — раніше
        /// вечір при відбої о 23:00 мав ключ `night`, і тижневі медіани ділились на два «вечори».
        public var key: String {
            switch self {
            case .morning: return DayPart.noon.key
            case .day: return DayPart.afternoon.key
            case .evening: return DayPart.evening.key
            }
        }

        /// Ніч до полудня — це ранок до підйому, після — вечір до відбою.
        static func of(_ part: DayPart, fromMinute: Int) -> Kind {
            switch part {
            case .morning, .noon: return .morning
            case .afternoon: return .day
            case .evening: return .evening
            case .night: return fromMinute < dayStartMinute ? .morning : .evening
            }
        }
    }

    public let kind: Kind
    public let parts: [DayPart]
    /// Межі за розкладом — від них рахується ціль і дедлайн чекпоінта.
    public let fromMinute: Int
    public let toMinute: Int
    /// `E(кінець) − E(початок)` в округлених значеннях — цілі блоків складаються точно в норму.
    public let targetMl: Int
    /// Межі зарахування порцій: у першого блоку від 00:00, в останнього — до 24:00.
    let countsFromMinute: Int
    let countsToMinute: Int

    init(kind: Kind, parts: [DayPart], fromMinute: Int, toMinute: Int, targetMl: Int, opensDay: Bool, closesDay: Bool) {
        self.kind = kind
        self.parts = parts
        self.fromMinute = fromMinute
        self.toMinute = toMinute
        self.targetMl = targetMl
        countsFromMinute = opensDay ? 0 : fromMinute
        countsToMinute = closesDay ? 24 * 60 : toMinute
    }

    public var key: String { kind.key }
    /// «ранок» — для тексту посеред речення: «і ранок закрито».
    public var title: String { kind.title.lowercased() }

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
}

extension PaceCurve {
    /// Мінімальна тривалість блоку в межах активних годин (`minSegment`, §15.2).
    public static let minGoalBlockMinutes = 120

    /// Цілі частин доби за зростанням часу (§9, §32): ранок, день і вечір.
    public func goalBlocks(minSegmentMinutes: Int = PaceCurve.minGoalBlockMinutes) -> [GoalBlock] {
        typealias Draft = (kind: GoalBlock.Kind, parts: [DayPart], from: Int, to: Int)
        // Відрізки частин доби вже обрізані розкладом і йдуть за часом — лишається зібрати їх по видах.
        var blocks: [Draft] = []
        for segment in segments {
            let kind = GoalBlock.Kind.of(segment.part, fromMinute: segment.fromMinute)
            if let last = blocks.last, last.kind == kind {
                blocks[blocks.count - 1] = (kind, last.parts + [segment.part], last.from, segment.toMinute)
            } else {
                blocks.append((kind, [segment.part], segment.fromMinute, segment.toMinute))
            }
        }
        // Короткий зливається з сусідом (останній — з попереднім), поки коротких не лишиться. Назву
        // бере довший: підйом об 11:00 дає «день 11–17», а не «ранок 11–17».
        while blocks.count > 1,
              let index = blocks.firstIndex(where: { $0.to - $0.from < minSegmentMinutes }) {
            let other = index < blocks.count - 1 ? index + 1 : index - 1
            let (first, second) = (min(index, other), max(index, other))
            let kind = blocks[other].to - blocks[other].from >= blocks[index].to - blocks[index].from
                ? blocks[other].kind : blocks[index].kind
            blocks[first] = (kind, blocks[first].parts + blocks[second].parts, blocks[first].from, blocks[second].to)
            blocks.remove(at: second)
        }
        return blocks.enumerated().map { index, block in
            GoalBlock(kind: block.kind, parts: block.parts, fromMinute: block.from, toMinute: block.to,
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
