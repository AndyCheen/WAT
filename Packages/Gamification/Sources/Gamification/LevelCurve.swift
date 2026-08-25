import Foundation

/// Крива зростання рівнів. Винесена за протокол — баланс змінюється в одному місці.
public protocol LevelCurve: Sendable {
    /// Скільки XP треба, щоб перейти з рівня `level` на наступний.
    func xpToNext(after level: Int) -> Int
}

/// Лінійна з наростанням: 100, 150, 200, 250 … (PLAN.md §12.3).
public struct LinearLevelCurve: LevelCurve {
    public let base: Int
    public let step: Int

    public init(base: Int = 100, step: Int = 50) {
        self.base = base
        self.step = step
    }

    public func xpToNext(after level: Int) -> Int {
        base + step * max(0, level - 1)
    }
}

public struct LevelProgress: Equatable, Sendable {
    public let level: Int
    public let totalXp: Int
    public let xpIntoLevel: Int
    public let xpForNextLevel: Int

    public var fraction: Double {
        xpForNextLevel > 0 ? min(1, Double(xpIntoLevel) / Double(xpForNextLevel)) : 0
    }
    public var nextLevel: Int { level + 1 }
    public var xpLeft: Int { max(0, xpForNextLevel - xpIntoLevel) }
}

public enum LevelCalculator {
    /// Рівнів необмежено (ТЗ §5.2), тому рахуємо ітеративно від першого.
    public static func progress(totalXp: Int, curve: LevelCurve) -> LevelProgress {
        var level = 1
        var remaining = max(0, totalXp)
        var needed = curve.xpToNext(after: level)

        while remaining >= needed {
            remaining -= needed
            level += 1
            needed = curve.xpToNext(after: level)
        }

        return LevelProgress(level: level, totalXp: totalXp, xpIntoLevel: remaining, xpForNextLevel: needed)
    }

    /// Скільки сумарно XP потрібно, щоб досягти рівня `level`.
    public static func totalXpRequired(forLevel level: Int, curve: LevelCurve) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + curve.xpToNext(after: $1) }
    }
}
