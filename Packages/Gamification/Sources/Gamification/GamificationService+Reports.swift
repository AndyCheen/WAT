import Foundation
import Core
import Persistence

/// Гра за період — слайд «Гра» в звіті (SPEC-NOTIFICATIONS §11.3, блок 7).
public struct GamificationPeriodSummary: Equatable, Sendable {
    public struct Achievement: Equatable, Sendable {
        public let title: String
        public let emoji: String
    }

    public let xp: Int
    /// Рівень на початку й наприкінці періоду — «рівні 6→8».
    public let levelBefore: Int
    public let levelAfter: Int
    public let achievements: [Achievement]
    public let questsCompleted: Int
    /// Скільки XP лишилось до наступного рівня зараз — «до рівня 9 — 150 XP».
    public let xpToNextLevel: Int
    public let fractionIntoLevel: Double

    public var newLevels: Int { max(0, levelAfter - levelBefore) }
    public var isEmpty: Bool { xp == 0 && achievements.isEmpty && questsCompleted == 0 }
}

extension GamificationService {
    /// Рахується з журналу на льоту, як і решта звіту: звіти не зберігаються (§11.3).
    /// Рівні — з накопиченого XP до першого й після останнього дня, тож відкочений XP
    /// (undo порції) у звіт не потрапляє.
    public func periodSummary(days: [DayKey]) -> GamificationPeriodSummary {
        guard let first = days.first?.rawValue, let last = days.last?.rawValue else {
            return GamificationPeriodSummary(xp: 0, levelBefore: 1, levelAfter: 1, achievements: [], questsCompleted: 0,
                                             xpToNextLevel: 0, fractionIntoLevel: 0)
        }
        let entries = store.xpEntries(dayKey: nil).filter { $0.revertedAt == nil && $0.dayKey <= last }
        let before = entries.filter { $0.dayKey < first }.reduce(0) { $0 + $1.effectiveAmount }
        let during = entries.filter { $0.dayKey >= first }.reduce(0) { $0 + $1.effectiveAmount }

        let inPeriod: (Date?) -> Bool = { date in
            guard let date else { return false }
            let key = self.calendar.dayKey(for: date).rawValue
            return key >= first && key <= last
        }
        let achievements = store.allAchievementProgress()
            .filter { inPeriod($0.unlockedAt) }
            .sorted { ($0.unlockedAt ?? .distantPast) < ($1.unlockedAt ?? .distantPast) }
            .compactMap { AchievementCatalog.definition($0.defKey) }
            .map { GamificationPeriodSummary.Achievement(title: $0.title, emoji: $0.emoji) }
        let quests = store.quests(scope: nil, periodKey: nil).filter { inPeriod($0.completedAt) }.count

        let progress = xp.progress()
        return GamificationPeriodSummary(
            xp: during,
            levelBefore: LevelCalculator.progress(totalXp: before, curve: xp.curve).level,
            levelAfter: LevelCalculator.progress(totalXp: before + during, curve: xp.curve).level,
            achievements: achievements,
            questsCompleted: quests,
            xpToNextLevel: progress.xpLeft,
            fractionIntoLevel: progress.fraction
        )
    }
}
