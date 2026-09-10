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

/// Подія, на яку екран відповідає вібрацією.
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

    /// Виконані завдання сховані, доки користувач не попросить показати.
    /// Стан екранний: новий день і новий запуск починаються з активного списку.
    public private(set) var showCompletedQuests = false

    /// Остання подія для гаптики. Читається екраном, не скидається вручну.
    public private(set) var pulse: HomePulse?
    public private(set) var toast: HomeToast?

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
        // Вікно закріплене на першому закритому дні, поки їх менше семи, далі ковзає (WAT-11).
        weekDots = services.calendar
            .slidingWindow(7, anchor: services.hydration.firstGoalMetDay())
            .map { services.hydration.snapshot(for: $0).goalMet }
    }

    // MARK: - Дії

    public func add(_ ml: Int) {
        let levelBefore = level.level
        let result = services.hydration.addIntake(amountMl: ml)
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }

        guard let result else { return }

        // Вібрація одна на дію — беремо найпомітнішу з подій.
        if level.level > levelBefore {
            showToast(HomeToast(message: "Рівень \(level.level)!", actionTitle: nil, restoreIntakeId: nil))
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

    /// Перемикання лише через `withAnimation` — інакше рядки зникають ривком.
    public func toggleCompletedQuests() {
        withAnimation(WTAnimation.fade) { showCompletedQuests.toggle() }
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

    // MARK: - Завдання

    public var visibleQuests: [QuestSnapshot] { showCompletedQuests ? quests : quests.active }
    public var completedQuestCount: Int { quests.completed.count }
    public var allQuestsDone: Bool { !quests.isEmpty && quests.active.isEmpty }

    // MARK: - Тости

    private func showToast(_ toast: HomeToast) {
        withAnimation(WTAnimation.toast) { self.toast = toast }
    }

    // MARK: - Дані для шторок

    public var achievements: [AchievementSnapshot] { services.gamification.achievementSnapshots() }
    public var unlockedCount: Int { achievements.filter(\.isUnlocked).count }
    public var weekSummary: WeekSummary { services.insights.weekSummary() }
    public var monthReport: CalendarMonthReport { services.insights.calendar(month: services.calendar.currentMonth) }

    /// Коли всі сім крапок залиті, вони вже нічого не додають — замінюємо їх числом серії.
    ///
    /// Умова навмисне на самих крапках, а не на `streak.current >= 7`: серія лишається
    /// живою до кінця доби, тож одразу після зриву сьомого дня лічильник ще показував би 7,
    /// і замість «шість закрито, сьогодні відкрито» користувач бачив би число.
    /// Іконку замість тимчасового числа зробить окрема задача.
    public var showsStreakCount: Bool { weekDots.allSatisfy { $0 } }
    public var streakLabel: String { "\(streak.current)" }

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
