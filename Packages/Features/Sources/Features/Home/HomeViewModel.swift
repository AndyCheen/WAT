import Foundation
import Observation
import SwiftUI
import Core
import Persistence
import Hydration
import Gamification
import Insights
import DesignSystem

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

/// Подія, на яку екран відповідає вібрацією та анімацією.
///
/// Одне поле замість розсипу лічильників: `id` робить кожен пульс унікальним,
/// тож два однакові додавання поспіль дають два окремі відгуки.
public struct HomePulse: Equatable, Identifiable {
    public enum Kind: Equatable {
        case added(Int)
        case goalReached
        case levelUp(Int)
        case removed
        /// Порція вийшла за стелю 120 % — зараховано менше, ніж випито.
        case capped
    }

    public let id = UUID()
    public let kind: Kind
}

/// Тост із можливістю скасувати останню дію.
public struct HomeToast: Equatable, Identifiable {
    public let id = UUID()
    public let message: String
    public let actionTitle: String?
    /// Порція, яку поверне «Скасувати».
    public let restoreIntakeId: UUID?
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

    /// Остання подія для гаптики й анімації. Читається екраном, не скидається вручну.
    public private(set) var pulse: HomePulse?
    public private(set) var toast: HomeToast?
    public private(set) var isCelebrating = false

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
        let levelBefore = level.level
        let result = services.hydration.addIntake(amountMl: ml)
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }

        guard let result else { return }
        let leveledUp = level.level > levelBefore

        // Закриття норми дає більшість денного XP, тому рівень часто піднімається
        // тією ж порцією. Це різні канали: святкування показує виконану норму,
        // тост — новий рівень, і одне не має глушити інше.
        if result.goalJustReached { celebrate() }
        if leveledUp {
            showToast(HomeToast(message: "Рівень \(level.level)!", actionTitle: nil, restoreIntakeId: nil))
        }

        // Вібрація одна на дію — беремо найпомітнішу з подій.
        if leveledUp {
            pulse = HomePulse(kind: .levelUp(level.level))
        } else if result.goalJustReached {
            pulse = HomePulse(kind: .goalReached)
        } else if result.cappedAmountMl > 0 {
            pulse = HomePulse(kind: .capped)
        } else {
            pulse = HomePulse(kind: .added(ml))
        }
    }

    public func confirmCustom() {
        add(Intake.clamp(customAmount))
        dismissSheet()
    }

    public func stepCustom(_ delta: Int) {
        customAmount = max(Intake.minAmountMl, min(Intake.maxAmountMl, customAmount + delta))
    }

    public func remove(id: UUID) {
        guard services.hydration.removeIntake(id: id) != nil else { return }
        openHistoryId = nil
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }

        pulse = HomePulse(kind: .removed)
        // Видалення мʼяке (`Intake.deletedAt`), тому шлях назад є — просто його досі не пропонували.
        showToast(HomeToast(message: "Порцію видалено", actionTitle: "Скасувати", restoreIntakeId: id))
    }

    public func restore(id: UUID) {
        guard services.hydration.restoreIntake(id: id) != nil else { return }
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }
        pulse = HomePulse(kind: .added(0))
    }

    public func undoToast() {
        guard let id = toast?.restoreIntakeId else { return }
        restore(id: id)
    }

    public func dismissToast() {
        withAnimation(WTAnimation.toast) { toast = nil }
    }

    public func toggleHistory(id: UUID) {
        openHistoryId = openHistoryId == id ? nil : id
    }

    public func changeGoal(by delta: Int) {
        services.hydration.setGoal(day.goalMl + delta)
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }
    }

    public func markAchievementsSeen() {
        services.gamification.markAchievementsSeen()
        hasNewAchievements = false
    }

    // MARK: - Шторки

    /// Присвоєння `sheet` напряму не анімувалося — `WTSheet` має перехід,
    /// але без `withAnimation` він ніколи не програвався.
    public func present(_ sheet: HomeSheet) {
        withAnimation(WTAnimation.sheet) { self.sheet = sheet }
    }

    public func dismissSheet() {
        withAnimation(WTAnimation.sheet) { sheet = nil }
    }

    // MARK: - Святкування й тости

    private func celebrate() {
        withAnimation(WTAnimation.fade) { isCelebrating = true }
    }

    public func finishCelebration() {
        withAnimation(WTAnimation.fade) { isCelebrating = false }
    }

    private func showToast(_ toast: HomeToast) {
        withAnimation(WTAnimation.toast) { self.toast = toast }
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

    /// Пояснення до стелі 120 %: без нього незрозуміло, чому відсоток перестав рости.
    public var cappedNote: String? {
        guard day.isCapped else { return nil }
        return "Випито \(Volume.litersLabel(day.totalMl, fractionDigits: 1)) л — зараховано 120 % норми"
    }
}
