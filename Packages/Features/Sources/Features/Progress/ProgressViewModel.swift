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
    /// Інвентар, картка й дія з призом — спільні з екраном «Призи».
    public let prizes: PrizeInventoryModel
    public private(set) var achievements: [AchievementSnapshot] = []
    public private(set) var nextReward: (level: Int, rewards: [LevelRewardSnapshot])

    /// Один прапорець на весь блок «ЗАВДАННЯ» — денні й тижневі ховаються разом,
    /// два окремі перемикачі в одній секції читались би як помилка.
    public private(set) var showCompletedQuests = false

    public var showLevelRewards = false
    /// Картка деталей, відкрита з бейджа вітрини — прямо тут, без переходу на 2e.
    public private(set) var selectedAchievement: AchievementSnapshot?

    public init(services: AppServices) {
        self.services = services
        self.prizes = PrizeInventoryModel(services: services)
        self.level = services.gamification.levelProgress()
        self.nextReward = services.gamification.nextLevelRewards()
        reload()
    }

    public func reload() {
        level = services.gamification.levelProgress()
        dailyQuests = services.gamification.dailyQuests()
        weeklyQuests = services.gamification.weeklyQuests()
        prizes.reload()
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

    // MARK: - Досягнення

    /// Вітрина: відкриті й ті, що в процесі, до двох рядів (SPEC-ACHIEVEMENTS §4.1).
    public var achievementShowcase: [AchievementSnapshot] { achievements.showcase }

    /// Відкриття картки гасить крапку «нове» лише на цьому досягненні — але вітрину
    /// не перечитуємо до наступного візиту: переглянуте випадає з групи «щойно відкриті»,
    /// і сітка перетасовувалась би просто під модалкою. Так само поводиться екран 2e.
    public func selectAchievement(_ item: AchievementSnapshot?) {
        if let item, item.isNew {
            services.gamification.markAchievementSeen(key: item.key)
        }
        withAnimation(WTAnimation.fade) { selectedAchievement = item }
    }

    public var levelRewards: [LevelRewardSnapshot] { services.gamification.levelRewards() }
    public var xpLabel: String { "\(level.xpIntoLevel)/\(level.xpForNextLevel) XP до рівня \(level.nextLevel)" }
}
