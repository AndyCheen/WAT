import Foundation
import Observation
import Core
import Persistence
import Hydration
import Gamification

/// Сторінки режиму розробника — одна навігаційна гілка в `AppRoute`.
public enum DeveloperPage: Hashable, Sendable {
    case hub, day, achievements, quests
}

/// Режим розробника (WAT-68): стан для головної сторінки, досягнень і завдань. Дії — через `AppServices+Developer`,
/// модель лише перечитує знімки після кожної й після `epoch` (вікно відкриття, зсув годинника).
@MainActor
@Observable
final class DeveloperModel {
    let services: AppServices

    private(set) var level: LevelProgress
    private(set) var streak: StreakSummary
    private(set) var today: DaySnapshot
    private(set) var prizeCounts: [String: Int] = [:]
    private(set) var hasActiveBoost = false
    private(set) var achievements: [DeveloperAchievement] = []
    private(set) var quests: [DeveloperQuest] = []
    /// Час і зсув — збережені, а не похідні: годинник не спостережуваний, і без перечитування підпис не змінився б.
    private(set) var nowLabel = ""
    private(set) var clockOffsetLabel: String?

    var achievementFilter: AchievementFilter = .locked
    var search = ""

    enum AchievementFilter: CaseIterable {
        case locked, unlocked, secret, all

        var title: String {
            switch self {
            case .locked: return "Закриті"
            case .unlocked: return "Відкриті"
            case .secret: return "Таємні"
            case .all: return "Усі"
            }
        }
    }

    init(services: AppServices) {
        self.services = services
        level = services.gamification.levelProgress()
        streak = services.gamification.streakSummary()
        today = services.hydration.todaySnapshot()
        reload()
    }

    var epoch: Int { services.epoch }

    func reload() {
        level = services.gamification.levelProgress()
        streak = services.gamification.streakSummary()
        today = services.hydration.todaySnapshot()
        let inventory = services.gamification.prizeInventory()
        prizeCounts = Dictionary(inventory.ready.map { ($0.key, $0.count) }, uniquingKeysWith: +)
        hasActiveBoost = inventory.active.contains { RewardCatalog.boostKeys.contains($0.key) }
        achievements = services.gamification.developerAchievements()
        quests = services.gamification.developerQuests()
        nowLabel = DeveloperPresenter.moment(services.calendar.now, calendar: services.calendar,
                                             format: services.profile.timeFormat)
        clockOffsetLabel = services.developerClock.map { DeveloperPresenter.clockOffset($0.offset) }
    }

    // MARK: - Стан

    var levelLabel: String { DeveloperPresenter.level(level) }
    var streakLabel: String { ReportFormat.daysWord(streak.current, withNumber: true) }
    var todayLabel: String {
        DeveloperPresenter.volume(total: today.totalMl, counted: today.countedMl, goal: today.goalMl)
    }

    // MARK: - Дії

    func shiftClock(hours: Int) {
        services.developerShiftClock(by: TimeInterval(hours * 3600))
        reload()
    }

    func resetClock() {
        services.developerResetClock()
        reload()
    }

    func closeDays(_ count: Int) {
        services.developerCloseDays(count)
        reload()
    }

    func seedDemo() {
        services.developerSeedDemo()
        reload()
    }

    func grantPrize(_ key: String) {
        services.developerGrantPrize(key: key)
        reload()
    }

    func awardXp(_ amount: Int) {
        services.developerAwardXp(amount)
        reload()
    }

    func levelUp() {
        services.developerLevelUp()
        reload()
    }

    func stopBoost() {
        services.developerStopBoost()
        reload()
    }

    func showSchedule(_ demo: ScheduleSuggestionDemo) { services.showScheduleSuggestion(demo) }
    func tapNotification(_ type: NotificationType) { services.simulateNotificationTap(type) }

    /// Стирання — на наступному запуску (`DeveloperSettings.applyPendingReset`): сервіси тримають живі об'єкти бази,
    /// і стерти з-під них на ходу — це падіння. Тому застосунок закривається сам; відкрити його знову — справа людини.
    func reset(_ scope: EraseScope) {
        DeveloperSettings.pendingReset = scope
        DeveloperSettings.defaults.synchronize()
        exit(0)
    }

    // MARK: - Досягнення

    var unlockedCount: Int { achievements.filter(\.isUnlocked).count }

    var visibleAchievements: [DeveloperAchievement] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return achievements.filter { achievement in
            let matches: Bool
            switch achievementFilter {
            case .locked: matches = !achievement.isUnlocked
            case .unlocked: matches = achievement.isUnlocked
            case .secret: matches = achievement.isSecret
            case .all: matches = true
            }
            return matches && (query.isEmpty || achievement.title.lowercased().contains(query)
                || achievement.key.lowercased().contains(query))
        }
    }

    func toggle(_ achievement: DeveloperAchievement) {
        if achievement.isUnlocked {
            services.developerRelock(achievement: achievement.key)
        } else {
            services.developerUnlock(achievement: achievement.key)
        }
        reload()
    }

    // MARK: - Завдання

    /// Щоденні, тижневі й несподіване сьогодні — у порядку каталогу, як на дошці.
    var currentQuests: [DeveloperQuest] {
        quests.sorted { Self.catalogOrder[$0.snapshot.key] ?? .max < Self.catalogOrder[$1.snapshot.key] ?? .max }
    }

    func catalog(_ scope: QuestScope) -> [QuestDefinition] {
        QuestCatalog.active.filter { $0.scope == scope }
    }

    func questTitle(_ quest: DeveloperQuest) -> String {
        QuestPresenter.title(quest.snapshot, unit: services.profile.volumeUnit, format: services.profile.timeFormat)
    }

    func questProgress(_ quest: DeveloperQuest) -> String {
        "\(DeveloperPresenter.questState(quest.state)) · "
            + QuestPresenter.progressLabel(quest.snapshot, unit: services.profile.volumeUnit)
            + " · \(quest.snapshot.rewardXp) XP"
    }

    /// `false` — пікер не зміг видати: тижневе за 3 дні до кінця тижня, несподіване не сьогодні.
    @discardableResult
    func issue(_ key: String, delayMinutes: Int = 0) -> Bool {
        let issued = services.developerIssueQuest(key: key, delayMinutes: delayMinutes)
        reload()
        return issued
    }

    func complete(_ quest: DeveloperQuest) {
        services.developerComplete(quest: quest.id)
        reload()
    }

    func cancel(_ quest: DeveloperQuest) {
        services.developerCancel(quest: quest.id)
        reload()
    }

    private static let catalogOrder = Dictionary(QuestCatalog.all.enumerated().map { ($1.key, $0) },
                                                 uniquingKeysWith: { first, _ in first })
}
