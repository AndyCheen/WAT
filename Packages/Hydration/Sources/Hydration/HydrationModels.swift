import Foundation
import Core

/// Знімок стану дня для UI. View ніколи не працює з `@Model`-обʼєктами напряму.
public struct DaySnapshot: Equatable, Sendable {
    public let dayKey: DayKey
    public let goalMl: Int
    public let totalMl: Int
    public let countedMl: Int
    public let entriesCount: Int
    public let partTotals: [Int]
    public let isCapped: Bool

    public init(
        dayKey: DayKey,
        goalMl: Int,
        totalMl: Int,
        countedMl: Int,
        entriesCount: Int,
        partTotals: [Int],
        isCapped: Bool
    ) {
        self.dayKey = dayKey
        self.goalMl = goalMl
        self.totalMl = totalMl
        self.countedMl = countedMl
        self.entriesCount = entriesCount
        self.partTotals = partTotals
        self.isCapped = isCapped
    }

    public var completionPct: Int {
        guard goalMl > 0 else { return 0 }
        return Int((Double(countedMl) / Double(goalMl) * 100).rounded())
    }

    public var progressFraction: Double {
        guard goalMl > 0 else { return 0 }
        return min(1, Double(countedMl) / Double(goalMl))
    }

    public var goalMet: Bool { countedMl >= goalMl }
    public var remainingMl: Int { max(0, goalMl - countedMl) }

    public static func empty(dayKey: DayKey, goalMl: Int) -> DaySnapshot {
        DaySnapshot(
            dayKey: dayKey, goalMl: goalMl, totalMl: 0, countedMl: 0,
            entriesCount: 0, partTotals: [0, 0, 0, 0, 0], isCapped: false
        )
    }
}

/// Порція у вигляді, придатному для рядка історії.
public struct IntakeSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let amountMl: Int
    public let createdAt: Date
    public let timeLabel: String

    public init(id: UUID, amountMl: Int, createdAt: Date, timeLabel: String) {
        self.id = id
        self.amountMl = amountMl
        self.createdAt = createdAt
        self.timeLabel = timeLabel
    }
}

/// Результат додавання порції — на нього реагують гейміфікація та UI.
public struct IntakeResult: Sendable {
    public let intakeId: UUID
    public let day: DaySnapshot
    public let goalJustReached: Bool
    public let cappedAmountMl: Int
}
