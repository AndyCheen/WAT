import Foundation
import DesignSystem
import SwiftUI
import Observation
import Core
import Gamification

@MainActor
@Observable
public final class ProgressViewModel {
    private let services: AppServices

    public private(set) var level: LevelProgress
    public private(set) var dailyQuests: [QuestSnapshot] = []
    public private(set) var weeklyQuests: [QuestSnapshot] = []
    public private(set) var prizes: [RewardSnapshot] = []
    public private(set) var achievements: [AchievementSnapshot] = []
    public private(set) var nextReward: (level: Int, rewards: [LevelRewardSnapshot])

    /// Один прапорець на весь блок «ЗАВДАННЯ» — денні й тижневі ховаються разом,
    /// два окремі перемикачі в одній секції читались би як помилка.
    public private(set) var showCompletedQuests = false

    public var showAllAchievements = false
    public var showLevelRewards = false

    public init(services: AppServices) {
        self.services = services
        self.level = services.gamification.levelProgress()
        self.nextReward = services.gamification.nextLevelRewards()
        reload()
    }

    public func reload() {
        level = services.gamification.levelProgress()
        dailyQuests = services.gamification.dailyQuests()
        weeklyQuests = services.gamification.weeklyQuests()
        prizes = services.gamification.prizes()
        achievements = services.gamification.achievementSnapshots()
        nextReward = services.gamification.nextLevelRewards()
    }


    // MARK: - Завдання

    /// Перемикання лише через `withAnimation` — інакше рядки зникають ривком.
    public func toggleCompletedQuests() {
        withAnimation(WTAnimation.fade) { showCompletedQuests.toggle() }
    }

    public var visibleDailyQuests: [QuestSnapshot] {
        showCompletedQuests ? dailyQuests : dailyQuests.active
    }

    public var visibleWeeklyQuests: [QuestSnapshot] {
        showCompletedQuests ? weeklyQuests : weeklyQuests.active
    }

    public var completedQuestCount: Int { dailyQuests.completed.count + weeklyQuests.completed.count }

    // MARK: - Анімовані переходи

    /// Прапорці шторок присвоювались напряму, тому переходи `WTSheet`/`WTModal`
    /// ніколи не програвались. Тепер будь-яка зміна йде через пружину дизайн-системи.
    public func present(_ flag: ReferenceWritableKeyPath<ProgressViewModel, Bool>) {
        withAnimation(WTAnimation.sheet) { self[keyPath: flag] = true }
    }

    public func dismiss(_ flag: ReferenceWritableKeyPath<ProgressViewModel, Bool>) {
        withAnimation(WTAnimation.sheet) { self[keyPath: flag] = false }
    }
    public var unlockedAchievements: [AchievementSnapshot] { achievements.filter(\.isUnlocked) }
    public var unlockedCount: Int { unlockedAchievements.count }
    public var totalCount: Int { achievements.count }
    public var levelRewards: [LevelRewardSnapshot] { services.gamification.levelRewards() }
    public var xpLabel: String { "\(level.xpIntoLevel)/\(level.xpForNextLevel) XP до рівня \(level.nextLevel)" }

    public func activate(prize: RewardSnapshot) {
        services.gamification.activatePrize(id: prize.id)
        services.touch()
        reload()
    }
}
