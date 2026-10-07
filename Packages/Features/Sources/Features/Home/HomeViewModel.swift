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
    /// Вікно «Склянка» на весь екран — лише з ранкової склянки (§7.1, рішення від 05.10.2026).
    case glass
    /// Вікно «Графік дня» на весь екран — пропозиція змінити підйом чи відбій (WAT-41, §27).
    case schedule
    public var id: Int {
        switch self {
        case .custom: return 0
        case .calendar: return 1
        case .settings: return 2
        case .stats: return 3
        case .permission: return 4
        case .glass: return 5
        case .schedule: return 6
        }
    }
}

/// Крок вікна «Склянка»: спершу — один раз — яка в тебе склянка, далі — скільки з неї.
public enum GlassStage: Equatable {
    case calibrate
    case pour
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
        /// Новий рівень дав вибір чи 🎁 — 3f з відкритим вікном «Шлях рівнів» (SPEC-PRIZES §16.6).
        case showLevelRoad
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

    /// Крива темпу й порції сьогодні — для капсули частини доби (WAT-40). Сам стан рахується
    /// на кожну хвилину в `dayPartLine()`: час іде без дії користувача, а таймера в моделі немає.
    private var dayCurve: PaceCurve?
    private var dayPortions: [TimedPortion] = []

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
    @ObservationIgnored public var onOpenLevelRoad: () -> Void = {}
    @ObservationIgnored public var onOpenNotifications: () -> Void = {}
    /// Шторка дозволу чекає, поки зникне тост чи картка досягнення: першу порцію майже завжди
    /// святкує «Перша крапля», і шторка поверх тоста сховала б його.
    private var permissionOfferPending = false
    public var openHistoryId: UUID?
    public var customAmount: Int = 300

    // Вікно «Склянка» (§7.1).
    public var glassStage: GlassStage = .pour
    public var glassAmount: Int = 250
    public var calibrationChoice: Int = 250
    /// Записаний об'єм — поки показується «+250»; потім вікно закривається само.
    public var glassRecorded: Int?

    // Вікно «Графік дня» (WAT-41).
    public private(set) var scheduleOffer: ScheduleSuggestion?
    /// Що буде збережено: пропозиція, а після «Налаштувати» — підправлене кроками.
    public private(set) var scheduleDraft = DaySchedule.weekdayDefault
    public private(set) var scheduleAdjusting = false
    /// Відкриття, на якому вже перевіряли пропозицію: повернення на головний з іншого екрана — не відкриття.
    private var scheduleCheckedActivation: Int?

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
        dayCurve = services.hydration.schedule(for: day.dayKey).curve(goalMl: day.goalMl)
        dayPortions = history.map { TimedPortion(minute: services.calendar.minuteOfDay($0.createdAt), ml: $0.amountMl) }
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
        case .showLevelRoad:
            onOpenLevelRoad()
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
            if let toast = levelRewardToast(level) { return toast }
            let bonus = unlocked.bounceBackXp.map { " · 🔁 Знову в ритмі: +\($0) XP" } ?? ""
            return HomeToast(message: "Рівень \(level)!\(bonus)")
        }
        if let toast = achievementToast(unlocked.achievements) { return toast }
        if let xp = unlocked.bounceBackXp {
            return HomeToast(message: "🔁 Знову в ритмі: +\(xp) XP")
        }
        return nil
    }

    /// Тост рівня з призом (SPEC-PRIZES §16.6). Приз важливіший за «Знову в ритмі»: бонус XP уже нараховано,
    /// а вибір чи 🎁 без підказки можна й не помітити — тож бонус у такому тості не дописуємо, щоб не в два рядки.
    static func levelRewardToast(_ level: Int) -> HomeToast? {
        switch LevelRoadCatalog.node(forLevel: level) {
        case .mystery?:
            return HomeToast(message: "Рівень \(level)! 🎁 Чекає таємний приз",
                             actionTitle: "Відкрити", action: .showLevelRoad)
        case .choice(let grants)?:
            let emojis = grants.compactMap { RewardCatalog.definition($0.key)?.emoji }.joined(separator: " або ")
            return HomeToast(message: "Рівень \(level)! Обери приз: \(emojis)",
                             actionTitle: "Обрати", action: .showLevelRoad)
        case .prize(let grant)?:
            guard let definition = RewardCatalog.definition(grant.key) else { return nil }
            return HomeToast(message: "Рівень \(level)! \(definition.emoji) \(definition.title) — у призах",
                             actionTitle: "Подивитись", action: .showPrize(grant.key))
        case nil:
            return nil
        }
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
        case .glass:
            openGlass()
        case .schedule(let offer):
            openSchedule(offer)
        }
    }

    // MARK: - Вікно «Склянка» (§7.1)

    public static let calibrationChoices = [200, 250, 300, 350, 400]
    private static let fractionMarks: [(title: String, fraction: Double)] = [("Повна", 1), ("¾", 0.75), ("½", 0.5), ("¼", 0.25)]
    private static let fractionWords: [Double: String] = [1: "повна склянка", 0.75: "три чверті", 0.5: "пів склянки",
                                                          0.25: "чверть склянки"]

    public var glassCapacity: Int { services.profile.glassMl }

    /// Частки, що дають щонайменше мінімум порції: при склянці < 200 мл «¼» зникає (§7.1, п. 2).
    public var glassFractions: [(title: String, fraction: Double)] {
        Self.fractionMarks.filter { glassMl(for: $0.fraction) >= Intake.minAmountMl }
    }

    /// Частка → мілілітри, округлено до 5: «¼» від 250 — 60, а не 62,5.
    public func glassMl(for fraction: Double) -> Int {
        Int((Double(glassCapacity) * fraction / 5).rounded()) * 5
    }

    /// «пів склянки» — коли об'єм точно дорівнює частці.
    public var glassFractionWord: String? {
        glassFractions.first { glassMl(for: $0.fraction) == glassAmount }.flatMap { Self.fractionWords[$0.fraction] }
    }

    public var glassAccessibilityValue: String {
        ["\(glassAmount) мл", glassFractionWord].compactMap { $0 }.joined(separator: ", ")
    }

    func openGlass() {
        glassRecorded = nil
        glassAmount = glassCapacity
        calibrationChoice = Self.calibrationChoices.contains(glassCapacity) ? glassCapacity : 250
        glassStage = services.profile.glassConfirmed ? .pour : .calibrate
        present(.glass)
    }

    public func selectGlassFraction(_ fraction: Double) {
        glassAmount = glassMl(for: fraction)
    }

    public func recalibrateGlass() {
        calibrationChoice = Self.calibrationChoices.contains(glassCapacity) ? glassCapacity : 250
        withAnimation(WTAnimation.fade) { glassStage = .calibrate }
    }

    /// «Готово» калібрування: склянку задано — вона ж і в сповіщеннях, і на екрані «Сповіщення».
    public func confirmCalibration() {
        services.profile.glassMl = calibrationChoice
        services.profile.glassConfirmed = true
        services.profiles.save()
        services.touch()
        glassAmount = calibrationChoice
        withAnimation(WTAnimation.fade) { glassStage = .pour }
    }

    /// Запис — той самий шлях, що в «Іншому», потім «+250» на мить, і вікно закривається само.
    public func confirmGlass() {
        let amount = glassAmount
        add(amount)
        withAnimation(WTAnimation.fade) { glassRecorded = amount }
        Task { [weak self] in
            try? await Task.sleep(for: Self.recordedHold)
            guard let self, self.sheet == .glass else { return }
            self.dismissSheet()
            self.glassRecorded = nil
            self.presentPendingPermissionOffer()
        }
    }

    static let recordedHold: Duration = .milliseconds(1100)

    // MARK: - Вікно «Графік дня» (WAT-41, §27)

    /// Скільки чекати після відкриття: тап по сповіщенню, що запустив застосунок, доходить до роутера
    /// трохи пізніше за перший кадр, і вікно не має його перекрити.
    static let scheduleOfferDelay: Duration = .milliseconds(800)

    /// Лише на «чистому» відкритті головного: не поверх «Склянки», звіту, шторки дозволу, картки чи тоста
    /// й не коли застосунок відкрили зі сповіщення — тоді людина прийшла по інше. Без сповіщення:
    /// застосунок і так відкривають щодня (§3.1, п. 1).
    func offerScheduleIfNeeded(activation: Int, isHomeOnTop: Bool) {
        guard scheduleCheckedActivation != activation else { return }
        scheduleCheckedActivation = activation
        guard isHomeOnTop, sheet == nil, toast == nil, achievementDetail == nil, !permissionOfferPending,
              services.router.pendingPath == nil, services.router.pendingHomeIntent == nil,
              let offer = services.scheduleOffer() else { return }
        services.markScheduleOfferShown(offer)
        openSchedule(offer)
    }

    func openSchedule(_ offer: ScheduleSuggestion) {
        scheduleOffer = offer
        scheduleDraft = offer.proposed
        scheduleAdjusting = false
        present(.schedule)
    }

    var scheduleContent: SchedulePresenter.Content? {
        scheduleOffer.map { SchedulePresenter.content($0, draft: scheduleDraft) }
    }

    /// «Налаштувати» — кроки часу прямо у вікні, без переходу в налаштування.
    public func adjustSchedule() {
        withAnimation(WTAnimation.fade) { scheduleAdjusting = true }
    }

    public func stepScheduleWake(_ direction: Int) {
        scheduleDraft = scheduleDraft.steppingWake(direction)
    }

    public func stepScheduleSleep(_ direction: Int) {
        scheduleDraft = scheduleDraft.steppingSleep(direction)
    }

    /// «Так, змінити» чи «Зберегти»: вікно закривається, тост — на головному, капсула частини доби
    /// одразу за новим розкладом.
    public func acceptSchedule() {
        guard let offer = scheduleOffer else { return }
        let schedule = scheduleDraft
        services.acceptScheduleOffer(offer, schedule: schedule)
        dismissSheet()
        withAnimation(WTAnimation.fade) { reload() }
        showToast(HomeToast(message: SchedulePresenter.toast(offer, schedule: schedule)))
    }

    public func declineSchedule() {
        services.declineScheduleOffer()
        dismissSheet()
    }

    /// ✕ — без відповіді: показ уже записано як «закрили», спитаємо через 7 днів.
    public func closeSchedule() {
        dismissSheet()
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

    // MARK: - Ритм дня (WAT-42, SPEC-NOTIFICATIONS §28)

    public var dayRhythmEnabled: Bool { services.profile.dayRhythmEnabled }

    /// Пропозиція «Рівні інтервали» — лише щойно після вимикання ритму: нагадування «за темпом»
    /// теж спираються на частини доби, але змінювати їх мовчки не можна, а питати щоразу — набридливо.
    public private(set) var offersIntervalReminders = false

    /// Вимкнено — режим «просто норма за день»: без чекпоінтів, XP і завдань частин доби, капсули
    /// й частин у звітах. Нарахований XP лишається; увімкнення повертає все з наступної порції.
    public func setDayRhythm(_ enabled: Bool) {
        services.profile.dayRhythmEnabled = enabled
        services.profiles.save()
        let settings = services.notifications.settings
        offersIntervalReminders = !enabled && services.profile.notificationsEnabled
            && settings.remindersEnabled && settings.reminderMode == .pace
        // Перепланування — чекпоінти зникають чи повертаються одразу, а не з наступною порцією.
        services.touch()
    }

    public func switchRemindersToInterval() {
        services.notifications.settings.reminderMode = .interval
        services.profiles.save()
        offersIntervalReminders = false
        services.touch()
    }

    // MARK: - Шторки

    /// Присвоєння `sheet` напряму не анімувалося — `WTSheet` має перехід,
    /// але без `withAnimation` він ніколи не програвався.
    public func present(_ sheet: HomeSheet) {
        withAnimation(WTAnimation.sheet) { self.sheet = sheet }
    }

    public func dismissSheet() {
        offersIntervalReminders = false
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

    /// Капсула частини доби на цю хвилину. Екран викликає її з `TimelineView` раз на хвилину;
    /// час — від `Clock`, а не з `TimelineView`, інакше `--uitest-now` не діяв би.
    func dayPartLine() -> DayPartLine? {
        // Режим «просто норма» (WAT-42): частин доби на головному немає.
        guard services.profile.dayRhythmEnabled else { return nil }
        let now = services.calendar.now
        let progress = dayCurve?.dayPartProgress(atMinute: services.calendar.minuteOfDay(now), portions: dayPortions)
        // XP — як нарахує `GamificationService`: серія на ціль частини не множить, буст — так.
        let xp = Int(Double(services.gamification.xp.rules.perDayPartGoal) * services.gamification.xp.boostMultiplier(at: now))
        return DayPartPresenter.line(progress, goalMet: day.goalMet, xp: xp)
    }

    /// Пояснення до стелі 120 %: без нього незрозуміло, чому відсоток перестав рости.
    public var cappedNote: String? {
        guard day.isCapped else { return nil }
        return "Випито \(Volume.litersLabel(day.totalMl, fractionDigits: 1)) л — зараховано 120 % норми"
    }
}
