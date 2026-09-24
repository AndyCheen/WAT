import Foundation
import Observation
import SwiftUI
import Core
import Persistence
import Hydration
import Gamification
import Insights
import DesignSystem

/// Шторки головного. Досягнень серед них немає: шторка-дубль екрана 2e з гіршим
/// набором функцій прибрана, до досягнень веде лише екран (SPEC-ACHIEVEMENTS §1).
public enum HomeSheet: Identifiable {
    case custom, calendar, settings, stats
    public var id: Int {
        switch self {
        case .custom: return 0
        case .calendar: return 1
        case .settings: return 2
        case .stats: return 3
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
        /// Відкрито досягнення. На дотик — як закрита норма, але не як рівень:
        /// рівень і досягнення мають відрізнятись (SPEC-ACHIEVEMENTS §8).
        case achievementUnlocked
        case removed
        /// Порція вийшла за стелю 120 % — зараховано менше, ніж випито.
        case capped
    }

    public let id = UUID()
    public let kind: Kind
}

/// Що показує індикатор серії в шапці: рядок крапок за останні дні чи число довгої серії.
public enum StreakIndicator: Equatable {
    case dots([Bool])
    case streak(Int)
}

/// Тост головного: скасування видалення, новий рівень, нове досягнення.
public struct HomeToast: Equatable, Identifiable {
    public enum Action: Equatable {
        /// Повернути видалену порцію.
        case restoreIntake(UUID)
        /// Одне досягнення — одразу його картка.
        case showAchievement(String)
        /// Кілька за одну дію — один тост, дія веде на екран 2e.
        case showAllAchievements
    }

    public let id = UUID()
    public let message: String
    public let actionTitle: String?
    public let action: Action?

    public init(message: String, actionTitle: String? = nil, action: Action? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    /// Порція, яку поверне «Скасувати».
    public var restoreIntakeId: UUID? {
        if case .restoreIntake(let id) = action { return id }
        return nil
    }
}

@MainActor
@Observable
public final class HomeViewModel {
    /// Довжина серії, з якої крапки поступаються місцем краплі з числом (WAT-10).
    /// Збігається з довжиною вікна крапок: сім залитих крапок уже не несуть інформації.
    static let streakDropThreshold = 7

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
    /// Картка досягнення, відкрита з тоста — поверх головного, без переходу.
    public private(set) var achievementDetail: AchievementSnapshot?
    /// Перехід на екран 2e — його робить `RootView`, модель лише просить.
    @ObservationIgnored public var onOpenAchievements: () -> Void = {}
    public var openHistoryId: UUID?
    public var customAmount: Int = 300

    public init(services: AppServices) {
        self.services = services
        self.day = services.hydration.todaySnapshot()
        self.level = services.gamification.levelProgress()
        reload()
        // Розблокування зі старту (демо-історія, стартовий `refresh`) — не заслуга
        // жодної дії на цьому екрані, тост за них був би незрозумілий.
        _ = services.gamification.takeRecentUnlocks()
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
        _ = services.gamification.takeRecentUnlocks()
        let result = services.hydration.addIntake(amountMl: ml)
        let unlocked = services.gamification.takeRecentUnlocks()
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }

        guard let result else { return }

        // Тост один на дію. Рівень важливіший: він рідший, а про нове досягнення
        // все одно нагадає крапка на краплі рівня в шапці.
        if level.level > levelBefore {
            showToast(HomeToast(message: "Рівень \(level.level)!"))
        } else if let toast = Self.achievementToast(unlocked) {
            showToast(toast)
        }

        // Вібрація одна на дію — беремо найпомітнішу з подій.
        if level.level > levelBefore {
            pulse = HomePulse(kind: .levelUp(level.level))
        } else if result.goalJustReached {
            pulse = HomePulse(kind: .goalReached)
        } else if !unlocked.isEmpty {
            pulse = HomePulse(kind: .achievementUnlocked)
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
        showToast(HomeToast(message: "Порцію видалено", actionTitle: "Скасувати", action: .restoreIntake(id)))
    }

    public func restore(id: UUID) {
        guard services.hydration.restoreIntake(id: id) != nil else { return }
        // Повернута порція може знову відкрити досягнення — але його вже раз святкували.
        _ = services.gamification.takeRecentUnlocks()
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }
        pulse = HomePulse(kind: .added(0))
    }

    public func performToastAction() {
        switch toast?.action {
        case .restoreIntake(let id):
            restore(id: id)
        case .showAchievement(let key):
            showAchievement(key: key)
        case .showAllAchievements:
            onOpenAchievements()
        case nil:
            break
        }
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

    // MARK: - Досягнення

    /// «🏅 Досягнення: Перша крапля» або «🏅 Нові досягнення: 2» (SPEC-ACHIEVEMENTS §8).
    static func achievementToast(_ unlocked: [AchievementSnapshot]) -> HomeToast? {
        switch unlocked.count {
        case 0:
            return nil
        case 1:
            return HomeToast(
                message: "🏅 Досягнення: \(unlocked[0].title)",
                actionTitle: "Подивитись", action: .showAchievement(unlocked[0].key)
            )
        default:
            return HomeToast(
                message: "🏅 Нові досягнення: \(unlocked.count)",
                actionTitle: "Подивитись", action: .showAllAchievements
            )
        }
    }

    /// Крапка «нове» гасне саме на переглянутому досягненні.
    public func showAchievement(key: String) {
        guard let item = services.gamification.achievementSnapshots().first(where: { $0.key == key }) else { return }
        services.gamification.markAchievementSeen(key: key)
        hasNewAchievements = services.gamification.hasUnseenAchievements
        withAnimation(WTAnimation.fade) { achievementDetail = item }
    }

    public func dismissAchievement() {
        withAnimation(WTAnimation.fade) { achievementDetail = nil }
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

    public var weekSummary: WeekSummary { services.insights.weekSummary() }
    public var monthReport: CalendarMonthReport { services.insights.calendar(month: services.calendar.currentMonth) }

    /// Від семи днів поспіль рядок крапок уже нічого не додає — замінюємо його числом
    /// серії з краплею (WAT-10).
    ///
    /// Крапля тримається, доки серія жива, — зокрема весь наступний день, поки норму
    /// ще не закрито. Умова на самих крапках («усі сім залиті») тут не годиться: вікно
    /// крапок ковзає разом із сьогоднішнім днем, тож іконка зникала б щоранку й
    /// поверталась аж по закритті норми.
    public var streakIndicator: StreakIndicator {
        isStreakAlive && streak.current >= Self.streakDropThreshold
            ? .streak(streak.current)
            : .dots(weekDots)
    }

    /// Серія переобчислюється лише під час дій користувача (`scenePhase` ще не обробляється),
    /// тому `streak.current` сам по собі може бути вчорашнім. Живою вважаємо серію, чий
    /// останній зарахований день — сьогодні або вчора.
    private var isStreakAlive: Bool {
        guard let last = streak.lastCountedDay else { return false }
        return (0...1).contains(services.calendar.daysBetween(last, services.calendar.today))
    }

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
