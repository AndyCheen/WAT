import Foundation
import Observation
import SwiftUI
import Core
import Persistence
import Hydration
import Gamification
import Insights
import Notifications
import DesignSystem
import Widgets

/// Шторки головного. Досягнень серед них немає: шторка-дубль екрана 2e з гіршим
/// набором функцій прибрана, до досягнень веде лише екран (SPEC-ACHIEVEMENTS §1). Налаштування —
/// теж екран, а не шторка (WAT-15).
public enum HomeSheet: Identifiable {
    case custom, calendar, stats
    /// «Нагадувати, коли забудеш про воду?» — після першої порції (SPEC-NOTIFICATIONS §16.5).
    case permission
    /// Вікно «Склянка» на весь екран — лише з ранкової склянки (§7.1, рішення від 05.10.2026).
    case glass
    /// Вікно «Графік дня» на весь екран — пропозиція змінити підйом чи відбій (WAT-41, §27).
    case schedule
    /// Вікно «Нагадувань забагато?» на весь екран — разове питання, коли нагадування не допомагають (WAT-67, §32).
    case reminderHelp
    public var id: Int {
        switch self {
        case .custom: return 0
        case .calendar: return 1
        case .stats: return 3
        case .permission: return 4
        case .glass: return 5
        case .schedule: return 6
        case .reminderHelp: return 7
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
        /// Дія виконала завдання, і нічого гучнішого вона не дала (SPEC-QUESTS §9.2).
        case questDone
        /// Дія відкрила досягнення — вібрує саме вікно відкриття, у мить появи (SPEC-ACHIEVEMENTS §8.6).
        case celebration
        /// Подарунок за повернення без досягнення — тост із призом (SPEC-NOTIFICATIONS §12.5 А).
        case gift
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

/// Тост головного: скасування видалення, новий рівень без досягнень, подарунок за повернення. Досягнення —
/// не тост, а вікно відкриття (WAT-60, SPEC-ACHIEVEMENTS §8).
public struct HomeToast: Equatable, Identifiable {
    public enum Action: Equatable {
        /// Повернути видалену порцію.
        case restoreIntake(UUID)
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
    /// Завдання головного (SPEC-QUESTS §9.1). Що з них видно — `questBlock()`: дедлайн минає й без дії.
    public private(set) var questBoard: QuestBoard = .empty
    public private(set) var weekDots: [Bool] = Array(repeating: false, count: 7)
    public private(set) var level: LevelProgress
    public private(set) var streak: StreakSummary = .empty
    public private(set) var quickAmounts: [Int] = []
    /// Підказки шторки «Інше» — свої, з екрана «Кнопки порцій» (WAT-45).
    public private(set) var customChips: [Int] = []
    /// Система об'єму (WAT-46); перечитується в `reload()` — зміна в налаштуваннях видна після «назад».
    public private(set) var volumeUnit: VolumeUnit = .milliliters
    /// Формат годинника людини (WAT-58) — капсула частини доби, вікно «Графік дня».
    public private(set) var timeFormat: TimeFormat = .hours24
    public private(set) var hasNewAchievements = false
    /// Крапка на кнопці «Знань» (SPEC-LEARN §3.1).
    public private(set) var hasLearnNews = false

    /// Крива темпу й порції сьогодні — для капсули частини доби (WAT-40). Сам стан рахується
    /// на кожну хвилину в `dayPartLine()`: час іде без дії користувача, а таймера в моделі немає.
    private var dayCurve: PaceCurve?
    private var dayPortions: [TimedPortion] = []

    /// Виконані завдання сховані, доки користувач не попросить показати.
    /// Стан екранний: новий день і новий запуск починаються з активного списку.
    public private(set) var showCompletedQuests = false
    /// Виконані дією на цьому екрані й ще не згорнуті в «Виконані · N» (§9.2).
    public private(set) var celebratingQuestIds: Set<UUID> = []
    /// Виконані тією самою дією, що відкрила вікно досягнення: святкують після нього. Поки чекають — лишаються в
    /// списку, щоб не зникнути й не з'явитися знову.
    public private(set) var pendingQuestIds: Set<UUID> = []

    /// Остання подія для гаптики. Читається екраном, не скидається вручну.
    public private(set) var pulse: HomePulse?
    /// Поки тост на екрані, вікно відкриття чекає: «Порцію видалено · Скасувати» й новий графік — спершу
    /// (SPEC-ACHIEVEMENTS §8.5).
    public private(set) var toast: HomeToast? {
        didSet { toast == nil ? services.endCelebrationPause(.homeToast) : services.beginCelebrationPause(.homeToast) }
    }

    /// Під шторкою чи вікном «Склянка» вікно відкриття не показується — чекає, поки вони закриються.
    public var sheet: HomeSheet? {
        didSet { sheet == nil ? services.endCelebrationPause(.homeSheet) : services.beginCelebrationPause(.homeSheet) }
    }
    /// Картка досягнення поверх головного — з тапу по сповіщенню-відлунню про вже відсвятковане.
    public private(set) var achievementDetail: AchievementSnapshot?
    /// Переходи робить `RootView`, модель лише просить.
    @ObservationIgnored public var onOpenPrize: (String) -> Void = { _ in }
    @ObservationIgnored public var onOpenLevelRoad: () -> Void = {}
    /// Шторка дозволу чекає, поки зникне тост, картка чи вікно відкриття: першу порцію майже завжди
    /// святкує «Перша крапля», і шторка поверх вікна сховала б його.
    private var permissionOfferPending = false
    public var openHistoryId: UUID?
    public var customAmount: Int = 300
    /// Точний ввід у «Інше» (WAT-50): набрані цифри, поки поле в фокусі; `nil` — поле показує `customAmount`.
    public private(set) var customTyped: String?
    /// Стерте до порожнього поле повертає попереднє число, а не нуль: передумати не має нічого міняти.
    @ObservationIgnored private var customBeforeTyping = 300

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
        questBoard = services.gamification.questBoard()
        level = services.gamification.levelProgress()
        streak = services.gamification.streakSummary()
        quickAmounts = services.hydration.quickAddAmounts()
        customChips = services.hydration.quickAddAmounts(.customSheet)
        volumeUnit = services.hydration.volumeUnit
        timeFormat = services.profile.timeFormat
        hasNewAchievements = services.gamification.hasUnseenAchievements
        hasLearnNews = services.hasLearnNews
        // Вікно закріплене на першому закритому дні, поки їх менше семи, далі ковзає (WAT-11).
        weekDots = services.calendar
            .slidingWindow(7, anchor: services.hydration.firstGoalMetDay())
            .map { services.hydration.snapshot(for: $0).goalMet }
    }

    // MARK: - Дії

    public func add(_ ml: Int, viaCustom: Bool = false) {
        let levelBefore = level.level
        let doneBefore = doneQuestIds
        // Попередня дія відкрила вікно, яке так і не показалось (порцію відкотили): її завдання вже не святкуємо.
        pendingQuestIds = []
        _ = services.gamification.takeRecentUnlocks()
        let result = services.hydration.addIntake(amountMl: ml)
        // «Своя мірка» — частина тієї самої дії, тож і тост у неї спільний.
        if viaCustom, let result { services.record(.customPortion(result.intakeId), announce: false) }
        let unlocked = services.gamification.takeRecentUnlocks()
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }

        guard let result else { return }

        // Відкрите дією — вікно на весь екран, і рівень з тієї самої дії — рядок у ньому (SPEC-ACHIEVEMENTS §8.1).
        // Тост — лише без досягнень: подарунок → рівень із призом → рівень → «Знову в ритмі».
        let levelUp = level.level > levelBefore ? level.level : nil
        let celebrating = services.presentCelebrations(context: .action, level: levelUp)
        // Тост подарунка рівня не називає — тож і рівень тоді ще не відсвятковано.
        let toastLevel = celebrating || unlocked.comebackGift != nil
            ? nil : levelUp.flatMap { services.claimLevelCelebration($0) ? $0 : nil }
        if !celebrating, let toast = Self.unlockToast(unlocked, levelUp: toastLevel) {
            showToast(toast)
        }
        offerNotificationsIfNeeded()

        // Завдання, закриті саме цією дією, святкують у рядку; поки на екрані вікно досягнення — після нього.
        let questsDone = doneQuestIds.subtracting(doneBefore)
        if celebrating {
            pendingQuestIds = questsDone
        } else {
            celebrateQuests(questsDone)
        }

        // Вібрація одна на дію: вікно вібрує саме, без нього закрита норма важливіша за рівень, рівень — за
        // завдання (П2 аудиту WAT-29, SPEC-QUESTS §9.2).
        if celebrating {
            pulse = HomePulse(kind: .celebration)
        } else if unlocked.comebackGift != nil {
            pulse = HomePulse(kind: .gift)
        } else if result.goalJustReached {
            pulse = HomePulse(kind: .goalReached)
        } else if let toastLevel {
            pulse = HomePulse(kind: .levelUp(toastLevel))
        } else if !questsDone.isEmpty {
            pulse = HomePulse(kind: .questDone)
        } else if result.cappedAmountMl > 0 {
            pulse = HomePulse(kind: .capped)
        } else {
            pulse = HomePulse(kind: .added(ml))
        }
    }

    /// Кнопка «Інше» — з останнім доданим через шторку об'ємом (WAT-45). Тап по сповіщенню йде
    /// через `apply(_:)` з типовою порцією P: текст сповіщення називає саме її (§6.4).
    public func openCustom() {
        customTyped = nil
        customAmount = services.hydration.customAmountStart()
        present(.custom)
    }

    public func confirmCustom() {
        guard isCustomAmountValid else { return }
        customTyped = nil
        let amount = customAmount
        services.hydration.rememberCustomAmount(amount)
        add(amount, viaCustom: true)
        dismissSheet()
    }

    /// ±50 мл або ±1 унц. (`VolumeSteps.custom`, WAT-46).
    public func stepCustom(up: Bool) {
        endCustomTyping()
        customAmount = services.hydration.steppedCustomAmount(customAmount, up: up)
    }

    public func selectCustom(_ ml: Int) {
        customTyped = nil
        customAmount = ml
    }

    // MARK: - Точний ввід у «Інше» (WAT-50)

    /// Без нього «Пі» (314 мл) і «Дзеркало» (паліндром за день) з інтерфейсу не виконати: степер і чипи — сітка 50 мл,
    /// а чотиризначного паліндрома, кратного 50, немає (SPEC-ACHIEVEMENTS-CATALOG §9). Цифри — в одиницях людини:
    /// в унціях набирають унції, а `customAmount` лишається в мілілітрах (WAT-46).
    public var customFieldText: String { customTyped ?? volumeUnit.number(customAmount) }

    /// Поза 50…2000 мл «Додати» неактивна: мовчки записати 50 замість набраного «5» — гірше, ніж не дати натиснути.
    public var isCustomAmountValid: Bool { Intake.isValid(customAmount) }

    /// Рядком, а не інтерполяцією в `Text`: та локалізувала б межу як «2 000». В унціях межі — цілі унції, що
    /// влазять у 50…2000 мл: «від 2 до 67 унц.», бо 1 унц. — це 30 мл, а 68 — вже 2011 мл.
    public var customUnitCaption: String {
        guard !isCustomAmountValid else { return volumeUnit.symbol }
        let low = volumeUnit.unitsRoundedUp(Intake.minAmountMl)
        let high = volumeUnit.isMetric
            ? Intake.maxAmountMl
            : Int((Double(Intake.maxAmountMl) / volumeUnit.mlPerUnit).rounded(.down))
        return "від \(low) до \(high) \(volumeUnit.symbol)"
    }

    /// Тап по числу: набране замінює значення, а не дописується до нього — поки нічого не набрано, видно попереднє.
    public func beginCustomTyping() {
        guard customTyped == nil else { return }
        customBeforeTyping = customAmount
        customTyped = ""
    }

    /// Лише цифри, без нулів попереду й не більше чотирьох: п'ята цифра однаково вивела б за 2000 мл,
    /// а вставлене «0,33 л» не має зламати поле.
    public func typeCustom(_ text: String) {
        // `TextField` пише в прив'язку й сам, на початку редагування, — те саме число, ще до зміни фокуса.
        // Прийняти це за ввід — і поле не очиститься, а набране допишеться до старого: «3» → «3300».
        guard customTyped != nil else { return }
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.drop(while: { $0 == "0" }).prefix(4))
        customTyped = digits
        customAmount = Int(digits).map { volumeUnit.milliliters(units: $0) } ?? customBeforeTyping
    }

    /// Клавіатуру сховали — недобране число стає в межі порції, а не лишає «Додати» неактивною.
    public func endCustomTyping() {
        guard customTyped != nil else { return }
        customTyped = nil
        customAmount = Intake.clamp(customAmount)
    }

    public func remove(id: UUID) {
        guard services.hydration.removeIntake(id: id) != nil else { return }
        openHistoryId = nil
        services.touch()
        withAnimation(WTAnimation.fade) { reload() }

        pulse = HomePulse(kind: .removed)
        // Видалення мʼяке (`Intake.deletedAt`), тому шлях назад є — просто його досі не пропонували.
        showToast(HomeToast(message: "Порцію видалено", actionTitle: "Скасувати", action: .restoreIntake(id)))
        // «Нерішучість» — вікном після тоста зі «Скасувати»: повернути порцію важливіше.
        services.presentCelebrations(context: .action)
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

    func dismissToastSilently() {
        toast = nil
    }

    /// Перемикання лише через `withAnimation` — інакше рядки зникають ривком.
    public func toggleCompletedQuests() {
        withAnimation(WTAnimation.fade) { showCompletedQuests.toggle() }
    }

    public func toggleHistory(id: UUID) {
        openHistoryId = openHistoryId == id ? nil : id
    }

    // MARK: - Досягнення

    /// Тост дії без досягнень: подарунок → рівень (+ «Знову в ритмі») → «Знову в ритмі» (SPEC-NOTIFICATIONS §12.5).
    /// Відкрите досягнення святкує вікно (WAT-60), а з ним рівень — рядком.
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

    /// Крапка «нове» гасне саме на переглянутому досягненні.
    public func showAchievement(key: String) {
        guard let item = services.gamification.achievementSnapshots().first(where: { $0.key == key }) else { return }
        services.gamification.markAchievementSeen(key: key)
        hasNewAchievements = services.gamification.hasUnseenAchievements
        withAnimation(WTAnimation.fade) { achievementDetail = item }
    }

    /// Вікно відкриття закрили: крапка «нове» за відсвятковане не горить, і шторка дозволу, що чекала, — тепер.
    public func celebrationDidClose() {
        hasNewAchievements = services.gamification.hasUnseenAchievements
        // Закрите вікно могло показати наступне — рядки чекають і його.
        if services.celebration == nil, !services.hasPendingCelebrations, !pendingQuestIds.isEmpty {
            celebrateQuests(pendingQuestIds)
            pendingQuestIds = []
        }
        presentPendingPermissionOffer()
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
            customTyped = nil
            customAmount = Intake.clamp(ml)
            present(.custom)
        case .achievement(let key):
            // Відлуння про ще не відсвятковане веде у вікно, а не в картку (SPEC-ACHIEVEMENTS §8.5).
            if !services.presentCelebrations(context: .whileAway) { showAchievement(key: key) }
        case .glass:
            openGlass()
        case .schedule(let offer):
            openSchedule(offer)
        }
    }

    // MARK: - Вікно «Склянка» (§7.1)

    /// В унціях — звичні там склянки 6…14 унц., а не перераховані мілілітри (WAT-46).
    public static func calibrationChoices(_ unit: VolumeUnit) -> [Int] {
        unit.isMetric ? [200, 250, 300, 350, 400] : [6, 8, 10, 12, 14].map { unit.milliliters(units: $0) }
    }

    public var calibrationChoices: [Int] { Self.calibrationChoices(volumeUnit) }

    /// Склянка, якої немає серед варіантів, — друга: 250 мл чи 8 унц..
    private var defaultCalibration: Int {
        calibrationChoices.contains(glassCapacity) ? glassCapacity : calibrationChoices[1]
    }

    /// Крок перетягування склянки: 25 мл чи унція.
    public var glassDragStepMl: Int { volumeUnit.isMetric ? 25 : Int(volumeUnit.mlPerUnit.rounded()) }
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
        [volumeUnit.portion(glassAmount), glassFractionWord].compactMap { $0 }.joined(separator: ", ")
    }

    func openGlass() {
        glassRecorded = nil
        glassAmount = glassCapacity
        calibrationChoice = defaultCalibration
        glassStage = services.profile.glassConfirmed ? .pour : .calibrate
        present(.glass)
    }

    public func selectGlassFraction(_ fraction: Double) {
        glassAmount = glassMl(for: fraction)
    }

    public func recalibrateGlass() {
        calibrationChoice = defaultCalibration
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
              services.celebration == nil, !services.hasPendingCelebrations,
              services.router.pendingPath == nil, services.router.pendingHomeIntent == nil else { return }
        if let offer = services.scheduleOffer() {
            services.markScheduleOfferShown(offer)
            openSchedule(offer)
        } else if services.shouldOfferReminderHelp {
            // Те саме «чисте відкриття», що й для графіка, і не в одне відкриття з ним (WAT-67, §32).
            services.markReminderHelpOffered()
            present(.reminderHelp)
        }
    }

    // MARK: - «Нагадувань забагато?» (WAT-67, §32)

    public func answerReminderHelp(_ choice: NotificationService.ReminderHelpChoice) {
        services.answerReminderHelp(choice)
        dismissSheet()
        if let message = ReminderHelpPresenter.toast(choice) { showToast(HomeToast(message: message)) }
    }

    func openSchedule(_ offer: ScheduleSuggestion) {
        scheduleOffer = offer
        scheduleDraft = offer.proposed
        scheduleAdjusting = false
        present(.schedule)
    }

    var scheduleContent: SchedulePresenter.Content? {
        scheduleOffer.map { SchedulePresenter.content($0, draft: scheduleDraft, format: services.profile.timeFormat) }
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
        // Тост — раніше, ніж вікно закриється: таємне «Свій ритм» чекає його кінця, новий графік важливіший.
        showToast(HomeToast(message: SchedulePresenter.toast(offer, schedule: schedule, format: services.profile.timeFormat)))
        dismissSheet()
        withAnimation(WTAnimation.fade) { reload() }
        services.presentCelebrations(context: .action)
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
        presentPendingPermissionOffer()
    }

    private func presentPendingPermissionOffer() {
        guard permissionOfferPending, sheet == nil, toast == nil, achievementDetail == nil,
              services.celebration == nil, !services.hasPendingCelebrations else { return }
        permissionOfferPending = false
        present(.permission)
    }

    /// «Увімкнути» — системний запит `[.alert, .sound]`.
    public func enableNotifications() {
        dismissSheet()
        Task { await services.requestNotificationAuthorization() }
    }

    /// «Не зараз» або тап повз шторку — спитаємо ще раз через 3 дні.
    public func postponeNotifications() {
        services.notifications.postponePermissionPrompt(at: services.calendar.now)
        dismissSheet()
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

    /// Блок на цю хвилину. Екран викликає його з `TimelineView`: рядок із минулим дедлайном зникає, поки екран
    /// відкритий. Час — від `Clock`, як у капсули частини доби.
    func questBlock() -> QuestBlock {
        QuestBlock.make(board: questBoard, now: services.calendar.now,
                        celebrating: celebratingQuestIds.union(pendingQuestIds), showCompleted: showCompletedQuests)
    }

    func isCelebrating(_ quest: QuestSnapshot) -> Bool { celebratingQuestIds.contains(quest.id) }

    /// Свято скінчилось — рядок згортається в «Виконані · N».
    public func finishQuestCelebration(_ id: UUID) {
        guard celebratingQuestIds.contains(id) else { return }
        _ = withAnimation(WTAnimation.collapse) { celebratingQuestIds.remove(id) }
    }

    /// XP, яке нарахує виконання зараз: буст і загальний множник — як у `XPEngine.award`, серія завдань не множить.
    func questXp(_ quest: QuestSnapshot) -> Int {
        let xp = services.gamification.xp
        return Int((Double(quest.rewardXp) * xp.boostMultiplier(at: services.calendar.now) * xp.rules.xpMultiplier).rounded())
    }

    func questTitle(_ quest: QuestSnapshot) -> String { QuestPresenter.title(quest, unit: volumeUnit, format: timeFormat) }
    func surpriseDetail(_ quest: QuestSnapshot) -> String {
        QuestPresenter.surpriseDetail(quest, unit: volumeUnit, format: timeFormat)
    }
    func surpriseAccessibilityLabel(_ quest: QuestSnapshot) -> String {
        QuestPresenter.surpriseAccessibilityLabel(quest, xp: questXp(quest), unit: volumeUnit, format: timeFormat)
    }
    /// Початок відліку картки — від `Clock`, як і решта часу екрана.
    var now: Date { services.calendar.now }
    func questProgress(_ quest: QuestSnapshot) -> String { QuestPresenter.progressLabel(quest, unit: volumeUnit) }
    func questAccessibilityLabel(_ quest: QuestSnapshot) -> String {
        QuestPresenter.accessibilityLabel(quest, xp: questXp(quest), unit: volumeUnit, format: timeFormat)
    }

    private var doneQuestIds: Set<UUID> {
        Set((questBoard.daily + questBoard.weekly + [questBoard.surprise].compactMap { $0 }).filter(\.isDone).map(\.id))
    }

    private func celebrateQuests(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        withAnimation(WTAnimation.fade) { celebratingQuestIds.formUnion(ids) }
    }

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
        guard volumeUnit.isMetric else {
            return "\(volumeUnit.number(day.countedMl)) / \(volumeUnit.number(day.goalMl)) \(VolumeUnit.ounceSymbol)"
        }
        return "\(Volume.litersLabel(day.countedMl)) / \(Volume.litersLabel(day.goalMl, fractionDigits: 1)) л"
    }

    /// Капсула частини доби на цю хвилину. Екран викликає її з `TimelineView` раз на хвилину;
    /// час — від `Clock`, а не з `TimelineView`, інакше `--uitest-now` не діяв би.
    func dayPartLine() -> DayPartLine? {
        // Режим «просто норма» (WAT-42): частин доби на головному немає.
        guard services.profile.dayRhythmEnabled else { return nil }
        let now = services.calendar.now
        let progress = dayCurve?.dayPartProgress(atMinute: services.calendar.minuteOfDay(now), portions: dayPortions)
        // XP — як нарахує `GamificationService`: серія на ціль частини не множить, буст — так.
        let xp = Int(Double(services.gamification.xp.rules.perDayPartGoal) * services.gamification.xp.boostMultiplier(at: now))
        return DayPartPresenter.line(progress, goalMet: day.goalMet, xp: xp, unit: volumeUnit, format: timeFormat)
    }

    func clock(_ minutes: Int) -> String { timeFormat.clock(minutes) }

    /// Пояснення до стелі 120 %: без нього незрозуміло, чому відсоток перестав рости.
    public var cappedNote: String? {
        guard day.isCapped else { return nil }
        let total = volumeUnit.format(day.totalMl) { "\(Volume.litersLabel($0, fractionDigits: 1)) л" }
        // Понад півтори норми — тихе «досить» замість самої арифметики (WAT-67): аудит 60 днів — хто пив 3,9 л порціями
        // по літру, не чув від застосунку жодного слова, а стеля зупиняла лише XP. Підпис, не тост: без зайвого шуму.
        if day.totalMl * 2 > day.goalMl * 3 { return "Випито \(total) — норму закрито з запасом. Далі — за відчуттям" }
        return "Випито \(total) — зараховано 120 % норми"
    }
}
