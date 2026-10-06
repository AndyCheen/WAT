import Foundation
import Core

// MARK: - Вузли шляху рівнів (SPEC-PRIZES §16)

/// Один рядок нагороди: приз і скільки штук. Набір «×2» — два однакові предмети в інвентарі.
public struct RewardGrant: Equatable, Hashable, Sendable {
    public let key: String
    public let count: Int

    public init(_ key: String, count: Int = 1) {
        self.key = key
        self.count = count
    }

    public static let freeze = RewardGrant(RewardCatalog.freezeKey)
    public static let boost = RewardGrant(RewardCatalog.boostKey)
    public static let triple = RewardGrant(RewardCatalog.tripleKey)
}

/// Вміст таємного призу з вагами. Ваги в сумі — 100, тож це відсотки.
public struct MysteryPool: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let grants: [RewardGrant]
        public let weight: Int
    }

    public let entries: [Entry]
    /// Великий — кожен 10-й рівень: ювілей, жодного одного простого призу.
    public let isGrand: Bool

    public var totalWeight: Int { entries.reduce(0) { $0 + $1.weight } }

    /// Звичайний (6, 15, 25…).
    public static let regular = MysteryPool(entries: [
        Entry(grants: [.boost], weight: 40),
        Entry(grants: [.freeze], weight: 30),
        Entry(grants: [RewardGrant(RewardCatalog.boostKey, count: 2)], weight: 15),
        Entry(grants: [RewardGrant(RewardCatalog.freezeKey, count: 2)], weight: 10),
        Entry(grants: [.triple], weight: 5)
    ], isGrand: false)

    /// Великий (10, 20, 30…).
    public static let grand = MysteryPool(entries: [
        Entry(grants: [.triple], weight: 30),
        Entry(grants: [RewardGrant(RewardCatalog.boostKey, count: 2)], weight: 25),
        Entry(grants: [RewardGrant(RewardCatalog.freezeKey, count: 2)], weight: 25),
        Entry(grants: [.freeze, .boost], weight: 20)
    ], isGrand: true)
}

/// Що дає рівень. Порожній рівень — `nil` у каталозі.
public enum LevelNode: Equatable, Sendable {
    /// Видається одразу, як досягнуто рівня.
    case prize(RewardGrant)
    /// «Один з двох»: нічого не видається, доки людина не обере (§16.3).
    case choice([RewardGrant])
    /// 🎁: вміст визначений наперед, відкривається дією (§16.2).
    case mystery(MysteryPool)

    /// Вибір і таємний чекають дії, приз — ні.
    public var needsAction: Bool {
        if case .prize = self { return false }
        return true
    }
}

/// Таблиця вузлів (SPEC-PRIZES §16.1). Декларативна, як квести й досягнення: баланс — рядок, а не код.
///
/// До 10-го рівня — приз через рівень: рівні там приходять майже щодня, і приз на кожному знецінювався б.
/// З 11-го — на кожному: рівні вже розтягує крива. Нові механіки вводяться рано й по одній: ⚡ на 2-му,
/// вибір на 4-му, 🎁 на 6-му.
public enum LevelRoadCatalog {
    static let onboarding: [Int: LevelNode] = [
        2: .prize(.boost),
        4: .choice([.freeze, .boost]),
        6: .mystery(.regular),
        8: .prize(.freeze),
        10: .mystery(.grand)
    ]

    /// Рівні 11–15, 16–20, …: ⚡ → вибір → ⚡ → 🧊 → 🎁.
    static let cycle: [LevelNode] = [
        .prize(.boost),
        .choice([.freeze, .boost]),
        .prize(.boost),
        .prize(.freeze),
        .mystery(.regular)
    ]

    public static let firstCycleLevel = 11

    public static func node(forLevel level: Int) -> LevelNode? {
        guard level >= 2 else { return nil }
        guard level >= firstCycleLevel else { return onboarding[level] }
        let node = cycle[(level - firstCycleLevel) % cycle.count]
        // Кожен 10-й рівень — великий таємний: ювілей.
        if case .mystery = node, level % 10 == 0 { return .mystery(.grand) }
        return node
    }

    /// Найближчий рівень із призом після `level`.
    public static func nextRewardLevel(after level: Int) -> Int {
        var next = max(1, level) + 1
        while node(forLevel: next) == nil { next += 1 }
        return next
    }

    /// Скільки призів показувати повністю наперед і скільки — у тумані (§16.4).
    public static let visibleAhead = 3
    public static let foggedAhead = 2
}

// MARK: - Таємний приз

/// Вміст таємного призу — чиста функція зерна профілю й рівня (§16.2).
///
/// Системного генератора випадкових чисел немає свідомо: тести детерміновані, а перевстановлення
/// чи повторне відкриття не перекидає скриню. Анімація лише показує вже визначене.
public enum MysteryRoll {
    public static func outcome(level: Int, seed: String, pool: MysteryPool) -> [RewardGrant] {
        let total = pool.totalWeight
        guard total > 0, let fallback = pool.entries.first?.grants else { return [] }
        var roll = Int(roll(level: level, seed: seed) % UInt64(total))
        for entry in pool.entries {
            if roll < entry.weight { return entry.grants }
            roll -= entry.weight
        }
        return fallback
    }

    /// 48 біт з детермінованого UUID. Байти 6 і 8 `DeterministicID` перезаписує версією й варіантом,
    /// тож беремо 0…5 — вони від хешу цілі.
    static func roll(level: Int, seed: String) -> UInt64 {
        let uuid = DeterministicID.uuid(from: "mystery:\(seed):\(level)").uuid
        let bytes = [uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5]
        return bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }
}

// MARK: - Знімок для вікна

/// Стан рівня на шляху (§16.4).
public enum LevelRoadStatus: Equatable, Sendable {
    /// Досягнуто, призу немає.
    case passed
    /// Досягнуто, приз в інвентарі (чи вже використаний).
    case claimed
    /// Досягнуто, вибір чи 🎁 ще не забрано.
    case pending
    /// Попереду, серед `visibleAhead` найближчих призів.
    case upcoming
    /// Попереду, без призу, до туману.
    case ahead
    /// За горизонтом: номер рівня видно, приз — ні.
    case fogged
}

/// Як отримано приз рівня — для підпису «Отримано» / «Обрано з двох» / «З таємного призу».
public enum LevelRoadClaim: Equatable, Sendable {
    case prize, choice, mystery
}

public struct LevelRoadNode: Equatable, Identifiable, Sendable {
    public let level: Int
    public let reward: LevelNode?
    public let status: LevelRoadStatus
    /// Що саме видано за рівень (порожньо, доки не забрано).
    public let claimed: [RewardGrant]

    public var id: Int { level }

    public var claimKind: LevelRoadClaim? {
        guard status == .claimed, let reward else { return nil }
        switch reward {
        case .prize: return .prize
        case .choice: return .choice
        case .mystery: return .mystery
        }
    }

    public init(level: Int, reward: LevelNode?, status: LevelRoadStatus, claimed: [RewardGrant] = []) {
        self.level = level
        self.reward = reward
        self.status = status
        self.claimed = claimed
    }
}

public struct LevelRoadSnapshot: Equatable, Sendable {
    public let progress: LevelProgress
    /// Від 1-го рівня до 5-го призу наперед.
    public let nodes: [LevelRoadNode]
    /// Куди прокрутити на відкритті: найраніший вузол, що чекає дії, інакше останній отриманий приз,
    /// інакше поточний рівень.
    public let focusLevel: Int

    public init(progress: LevelProgress, nodes: [LevelRoadNode], focusLevel: Int) {
        self.progress = progress
        self.nodes = nodes
        self.focusLevel = focusLevel
    }

    public var pending: [LevelRoadNode] { nodes.filter { $0.status == .pending } }

    /// Найближчий рівень із призом попереду — блок «НАГОРОДА НА РІВНІ N».
    public var nextReward: LevelRoadNode? {
        nodes.first { $0.level > progress.level && $0.reward != nil }
    }

    /// Будує шлях: стани, горизонт і фокус. Чиста функція — правила §16.4 тестуються без бази.
    public static func make(
        progress: LevelProgress,
        claimed: (Int) -> [RewardGrant]?
    ) -> LevelRoadSnapshot {
        let current = progress.level
        var nodes: [LevelRoadNode] = []
        for level in 1...current {
            let reward = LevelRoadCatalog.node(forLevel: level)
            guard let reward else {
                nodes.append(LevelRoadNode(level: level, reward: nil, status: .passed))
                continue
            }
            if let grants = claimed(level) {
                nodes.append(LevelRoadNode(level: level, reward: reward, status: .claimed, claimed: grants))
            } else {
                // Звичайний приз без запису — ще не видано (наприклад, рівень щойно прийшов);
                // показуємо як отриманий: `grantLevelRewards` видасть його в цій же дії.
                let status: LevelRoadStatus = reward.needsAction ? .pending : .claimed
                nodes.append(LevelRoadNode(level: level, reward: reward, status: status, claimed: reward.grants))
            }
        }

        var rewardsAhead = 0
        var level = current
        let horizon = LevelRoadCatalog.visibleAhead + LevelRoadCatalog.foggedAhead
        while rewardsAhead < horizon {
            level += 1
            let reward = LevelRoadCatalog.node(forLevel: level)
            let status: LevelRoadStatus
            if reward != nil {
                rewardsAhead += 1
                status = rewardsAhead <= LevelRoadCatalog.visibleAhead ? .upcoming : .fogged
            } else {
                status = rewardsAhead < LevelRoadCatalog.visibleAhead ? .ahead : .fogged
            }
            nodes.append(LevelRoadNode(level: level, reward: reward, status: status))
        }

        let focus = nodes.first { $0.status == .pending }?.level
            ?? nodes.last { $0.status == .claimed }?.level
            ?? current
        return LevelRoadSnapshot(progress: progress, nodes: nodes, focusLevel: focus)
    }
}

extension LevelNode {
    /// Що видасть звичайний приз; для вибору й таємного наперед невідомо.
    var grants: [RewardGrant] {
        if case .prize(let grant) = self { return [grant] }
        return []
    }
}
