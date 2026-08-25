import Foundation
import Observation
import Core
import Persistence
import Hydration
import Gamification
import Insights

public enum HomeSheet: Identifiable {
    case custom, calendar, settings, stats, achievements
    public var id: Int {
        switch self {
        case .custom: return 0
        case .calendar: return 1
        case .settings: return 2
        case .stats: return 3
        case .achievements: return 4
        }
    }
}

@MainActor
@Observable
public final class HomeViewModel {
    private let services: AppServices

    public private(set) var day: DaySnapshot
    public private(set) var history: [IntakeSnapshot] = []
    public private(set) var quests: [QuestSnapshot] = []
    public private(set) var weekDots: [Bool] = Array(repeating: false, count: 7)
    public private(set) var level: LevelProgress
    public private(set) var streak: StreakSummary = .empty
    public private(set) var quickAmounts: [Int] = []
    public private(set) var hasNewAchievements = false

    public var sheet: HomeSheet?
    public var openHistoryId: UUID?
    public var customAmount: Int = 300

    public init(services: AppServices) {
        self.services = services
        self.day = services.hydration.todaySnapshot()
        self.level = services.gamification.levelProgress()
        reload()
    }

    public func reload() {
        day = services.hydration.todaySnapshot()
        history = services.hydration.intakes(for: services.calendar.today)
        quests = services.gamification.dailyQuests()
        level = services.gamification.levelProgress()
        streak = services.gamification.streakSummary()
        quickAmounts = services.hydration.quickAddAmounts()
        hasNewAchievements = services.gamification.hasUnseenAchievements
        weekDots = services.calendar.recentDays(7).map { key in
            services.hydration.snapshot(for: key).goalMet
        }
    }

    // MARK: - Дії

    public func add(_ ml: Int) {
        services.hydration.addIntake(amountMl: ml)
        services.touch()
        reload()
    }

    public func confirmCustom() {
        add(Intake.clamp(customAmount))
        sheet = nil
    }

    public func stepCustom(_ delta: Int) {
        customAmount = max(Intake.minAmountMl, min(Intake.maxAmountMl, customAmount + delta))
    }

    public func remove(id: UUID) {
        services.hydration.removeIntake(id: id)
        openHistoryId = nil
        services.touch()
        reload()
    }

    public func toggleHistory(id: UUID) {
        openHistoryId = openHistoryId == id ? nil : id
    }

    public func changeGoal(by delta: Int) {
        services.hydration.setGoal(day.goalMl + delta)
        services.touch()
        reload()
    }

    public func markAchievementsSeen() {
        services.gamification.markAchievementsSeen()
        hasNewAchievements = false
    }

    // MARK: - Дані для шторок

    public var achievements: [AchievementSnapshot] { services.gamification.achievementSnapshots() }
    public var unlockedCount: Int { achievements.filter(\.isUnlocked).count }
    public var weekSummary: WeekSummary { services.insights.weekSummary() }
    public var monthReport: CalendarMonthReport { services.insights.calendar(month: services.calendar.currentMonth) }

    public var pctLabel: String { "\(day.completionPct)%" }
    public var volumeLabel: String {
        "\(Volume.litersLabel(day.countedMl)) / \(Volume.litersLabel(day.goalMl, fractionDigits: 1)) л"
    }
    public var goalLabel: String { "\(Volume.litersLabel(day.goalMl, fractionDigits: 1)) л" }
}
