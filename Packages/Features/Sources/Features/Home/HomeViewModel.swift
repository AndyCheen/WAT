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
    /// «Нагадувати, коли забудеш про воду?» — після першої порції (SPEC-NOTIFICATIONS §16.5).
    case permission
    public var id: Int {
        switch self {
        case .custom: return 0
        case .calendar: return 1
        case .settings: return 2
        case .stats: return 3
        case .permission: return 4
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
        /// Подарунок за повернення — картка призу (SPEC-NOTIFICATIONS §12.5 А).
        case showPrize(String)
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

    /// Дані застаріли не через дію на цьому екрані (нова доба, повернення з фону) — екран
    /// слухає це значення й викликає `reload()`.
    public var epoch: Int { services.epoch }

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
    /// Переходи робить `RootView`, модель лише просить.
    @ObservationIgnored public var onOpenAchievements: () -> Void = {}
    @ObservationIgnored public var onOpenPrize: (String) -> Void = { _ in }
    @ObservationIgnored public var onOpenNotifications: () -> Void = {}
    /// Шторка дозволу чекає, поки зникне тост чи картка досягнення: першу порцію майже завжди
    /// святкує «Перша крапля», і шторка поверх тоста сховала б його.
    private var permissionOfferPending = false
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

        // Тост один на дію. Подарунок за повернення — найрідкісніший і веде в призи;
        // рівень важливіший за досягнення: про нове досягнення все одно нагадає крапка
        // на краплі рівня в шапці. «Знову в ритмі» приєднується до тоста рівня — норма
        // наступного дня після пропуску майже завжди піднімає й рівень.
        if let toast = Self.unlockToast(unlocked, levelUp: level.level > levelBefore ? level.level : nil) {
            showToast(toast)
        }
        offerNotificationsIfNeeded()

        // Вібрація одна на дію — беремо найпомітнішу з подій.
        if level.level > levelBefore {
            pulse = HomePulse(kind: .levelUp(level.level))
        } else if result.goalJustReached {
            pulse = HomePulse(kind: .goalReached)
        } else if !unlocked.achievements.isEmpty || unlocked.comebackGift != nil {
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
        case .showPrize(let key):
            onOpenPrize(key)
        case nil:
            break
        }
    }

    public func dismissToast() {
        withAnimation(WTAnimation.toast) { toast = nil }
        presentPendingPermissionOffer()
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

    /// Тост за все, що відкрила дія: подарунок → рівень (+ «Знову в ритмі») → досягнення →
    /// «Знову в ритмі» (SPEC-NOTIFICATIONS §12.5).
    static func unlockToast(_ unlocked: RecentUnlocks, levelUp: Int?) -> HomeToast? {
        if let gift = unlocked.comebackGift {
            return HomeToast(message: "🎁 З поверненням! ⚡ Подвійний XP — у призах",
                             actionTitle: "Подивитись", action: .showPrize(gift.key))
        }
        if let level = levelUp {
            let bonus = unlocked.bounceBackXp.map { " · 🔁 Знову в ритмі: +\($0) XP" } ?? ""
            return HomeToast(message: "Рівень \(level)!\(bonus)")
        }
        if let toast = achievementToast(unlocked.achievements) { return toast }
        if let xp = unlocked.bounceBackXp {
            return HomeToast(message: "🔁 Знову в ритмі: +\(xp) XP")
        }
        return nil
    }

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
        presentPendingPermissionOffer()
    }

    // MARK: - Сповіщення (SPEC-NOTIFICATIONS)

    /// Тап по сповіщенню просить шторку «Інше» з типовою порцією чи картку досягнення.
    public func apply(_ intent: AppRouter.HomeIntent) {
        switch intent {
        case .customAmount(let ml):
            customAmount = Intake.clamp(ml)
            present(.custom)
        case .achievement(let key):
            showAchievement(key: key)
        }
    }

    /// На першому запуску системного запиту немає — шторка з поясненням після першої порції,
    /// а «Не зараз» відкладає її на 3 дні (§16.5).
    private func offerNotificationsIfNeeded() {
        guard services.notifications.shouldOfferPermission(at: services.calendar.now) else { return }
        permissionOfferPending = true
        if toast == nil, achievementDetail == nil { presentPendingPermissionOffer() }
    }

    private func presentPendingPermissionOffer() {
        guard permissionOfferPending, sheet == nil, toast == nil, achievementDetail == nil else { return }
        permissionOfferPending = false
        present(.permission)
    }

    /// «Увімкнути» — системний запит `[.alert, .sound]`.
    public func enableNotifications() {
        dismissSheet()
        Task { await services.notifications.requestAuthorization() }
    }

    /// «Не зараз» або тап повз шторку — спитаємо ще раз через 3 дні.
    public func postponeNotifications() {
        services.notifications.postponePermissionPrompt(at: services.calendar.now)
        dismissSheet()
    }

    /// Рядок «Нагадування» в налаштуваннях — вхід на екран «Сповіщення» (§15.1).
    public func openNotificationSettings() {
        dismissSheet()
        onOpenNotifications()
    }

    public var notificationsSummary: String {
        guard services.profile.notificationsEnabled else { return "Вимк." }
        return services.notifications.authorization == .denied ? "Без дозволу" : "Увімк."
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
