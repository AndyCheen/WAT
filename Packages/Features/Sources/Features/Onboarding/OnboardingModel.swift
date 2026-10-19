import Foundation
import Observation
import SwiftUI
import Core
import Persistence
import Hydration
import DesignSystem

/// Модель онбордингу (WAT-56, SPEC-ONBOARDING): крок, чернетка й підтверджені кроки. Нічого не пише сама —
/// усе одним проходом записує `AppServices.applyOnboarding`, коли людина дійшла до кінця чи пропустила решту.
@MainActor
@Observable
public final class OnboardingModel {
    /// Куди йти після закриття.
    public enum Exit: Equatable {
        case home
        /// «Як користуватися» на фініші — історія «Перші кроки» в «Знаннях» (SPEC-LEARN §3.2).
        case learn
    }

    let services: AppServices
    public let mode: OnboardingMode
    let baseline: OnboardingBaseline
    let goalMath: OnboardingGoal
    public var draft: OnboardingDraft
    /// Чернетка на відкритті: ✕ питає «Вийти без змін?», лише коли людина щось змінила сама. Розрахована норма,
    /// вибрана за замовчуванням замість типової, — пропозиція, а не її зміна.
    private let initialDraft: OnboardingDraft
    public private(set) var stepIndex = 0
    /// Напрям останнього переходу — щоб екран заїжджав з правильного боку.
    public private(set) var movesForward = true
    /// Діалог «Вийти без змін?» у повторному проході.
    public var isConfirmingExit = false
    /// Кроки, підтверджені «Далі»: на першому запуску «Пропустити» зберігає лише їх (§6).
    private(set) var confirmed: Set<OnboardingStep> = []
    /// «Не зараз» на кроці «Нагадування» вже натиснули в цьому проході.
    private var remindersPostponed = false
    /// Дозвіл змінюється поза моделлю (системний запит) — лічильник будить екран, коли запит закінчився.
    private var remindersRevision = 0
    private let onExit: (Exit) -> Void

    public init(services: AppServices, mode: OnboardingMode, onExit: @escaping (Exit) -> Void) {
        self.services = services
        self.mode = mode
        self.onExit = onExit
        let baseline = services.onboardingBaseline()
        self.baseline = baseline
        let goalMath = OnboardingGoal(baseline: baseline)
        self.goalMath = goalMath
        let draft = OnboardingDraft(
            answers: baseline.answers,
            goalChoice: OnboardingGoal.defaultChoice(baseline: baseline, calculated: goalMath.calculated(baseline.answers), mode: mode)
        )
        self.draft = draft
        initialDraft = draft
    }

    // MARK: - Крок і прогрес

    public var step: OnboardingStep { OnboardingCatalog.steps[stepIndex] }

    /// Номер питання серед усіх питань — для крапок «Сцени».
    var questionNumber: Int? { OnboardingCatalog.questions.firstIndex(of: step).map { $0 + 1 } }
    var questionCount: Int { OnboardingCatalog.questions.count }

    /// Заповнення сегмента розділу на смузі «Кроків»: пройдені кроки розділу плюс поточний.
    func progress(of chapter: OnboardingChapter) -> Double {
        let steps = OnboardingCatalog.steps(in: chapter)
        let reached = steps.filter { (OnboardingCatalog.steps.firstIndex(of: $0) ?? 0) <= stepIndex }.count
        return Double(reached) / Double(max(1, steps.count))
    }

    var header: OnboardingPresenter.Header {
        OnboardingPresenter.header(step, mode: mode, offersGoalChoice: offersGoalChoice, reminders: reminders)
    }

    /// Крок без верхньої панелі: вітання й фініш першого запуску. У повторному проході на фініші лишаються
    /// «‹» і ✕ — повернутися щось підправити.
    var hidesTopBar: Bool { step == .hello || (step == .done && mode == .firstRun) }

    // MARK: - Норма

    var calculatedGoalMl: Int { goalMath.calculated(draft.answers) }
    var goalMl: Int { goalMath.final(draft) }
    var offersGoalChoice: Bool { goalMath.offersChoice(draft, mode: mode) }
    /// ± діє на розраховану норму; поки вибрано «Залишити поточну», крокувати нічим.
    var canAdjustGoal: Bool { draft.goalChoice == .calculated }
    var goalParts: [OnboardingPresenter.PartRow] {
        OnboardingPresenter.partRows(goalMath.parts(draft.answers), answers: draft.answers)
    }

    func stepGoal(_ direction: Int) {
        let calculated = calculatedGoalMl
        let next = GoalRevision.clamp(calculated + draft.goalAdjustMl + direction * Self.goalStepMl)
        draft.goalAdjustMl = next - calculated
    }

    static let goalStepMl = 50

    /// Крок розкрився новими рядками — підпитання про стан, окремі вихідні. Каркас тоді докручує вміст донизу:
    /// інакше застереження й нові рядки лишались би під кнопкою «Далі».
    var expansion: [Bool] { [draft.answers.gender == .female, draft.answers.week.weekendEnabled] }

    // MARK: - Зміни

    var changes: [OnboardingChange] {
        OnboardingChanges.list(baseline: baseline, draft: draft, goal: goalMath)
    }

    // MARK: - Відповіді, яким потрібне перетворення

    /// Вага в одиницях людини — лінійка й «−1 / +1» крокують цілими кілограмами чи фунтами.
    var weightValue: Int {
        get { OnboardingPresenter.weightNumber(draft.answers.weightKg, draft.answers.massUnit) }
        set {
            let range = OnboardingPresenter.weightRange(draft.answers.massUnit)
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            guard clamped != weightValue else { return }
            draft.answers.weightKg = Mass.kilograms(clamped, from: draft.answers.massUnit)
        }
    }

    func stepWeight(_ direction: Int) {
        weightValue += direction
    }

    /// Колесо віку: «Не вказувати» — `nil`, колесо тоді стоїть на типовому віці, але притушене.
    var ageWheelValue: Int { draft.answers.age ?? OnboardingAnswers.typicalAge }

    func setAge(_ age: Int?) {
        draft.answers.age = age
    }

    enum TimeBound { case wake, sleep }

    /// Межі й крок — `DaySchedule`, ті самі, що на екрані «Сповіщення» й у вікні «Графік дня».
    func stepTime(_ bound: TimeBound, weekend: Bool, direction: Int) {
        var week = draft.answers.week
        var day = weekend ? week.weekend : week.weekday
        day = bound == .wake ? day.steppingWake(direction) : day.steppingSleep(direction)
        if weekend { week.weekend = day } else { week.weekday = day }
        draft.answers.week = week
    }

    // MARK: - «Зараз» і «Було» (§7.2)

    /// Поточне значення відповіді в повторному проході. На першому запуску позначок немає: там нічого «свого» ще нема.
    func isCurrent<Value: Equatable>(_ keyPath: KeyPath<OnboardingAnswers, Value>, _ value: Value) -> Bool {
        mode == .revisit && baseline.answers[keyPath: keyPath] == value
    }

    /// Позначка біля числа: «Зараз», «Типово» (вагу ще не вказували) чи «Було 78 кг».
    enum Mark: Equatable {
        case none, current, typical
        case was(String)
    }

    func mark(for step: OnboardingStep) -> Mark {
        let old = baseline.answers, new = draft.answers
        switch step {
        case .weight:
            let same = abs(old.weightKg - new.weightKg) < 0.05
            if mode == .firstRun || !baseline.weightKnown { return same ? .typical : .none }
            return same ? .current : .was(OnboardingPresenter.weight(old.weightKg, new.massUnit))
        case .age:
            guard mode == .revisit else { return .none }
            return old.age == new.age ? .current : .was(OnboardingPresenter.ageValue(old.age))
        default:
            return .none
        }
    }

    func timeMark(_ bound: TimeBound, weekend: Bool) -> Mark {
        guard mode == .revisit else { return .none }
        let old = weekend ? baseline.answers.week.weekend : baseline.answers.week.weekday
        let new = weekend ? draft.answers.week.weekend : draft.answers.week.weekday
        let oldValue = bound == .wake ? old.wakeMinutes : old.sleepMinutes
        let newValue = bound == .wake ? new.wakeMinutes : new.sleepMinutes
        // Окремі вихідні щойно ввімкнули — «зараз» для них нічого немає.
        if weekend && !baseline.answers.week.weekendEnabled { return .none }
        return oldValue == newValue ? .current : .was(OnboardingPresenter.clock(oldValue, draft.answers.timeFormat))
    }

    /// «↺ Як було» — повернути відповідь кроку до поточного значення.
    func revert(_ step: OnboardingStep) {
        switch step {
        case .weight: draft.answers.weightKg = baseline.answers.weightKg
        case .age: draft.answers.age = baseline.answers.age
        default: break
        }
    }

    func revertTime(_ bound: TimeBound, weekend: Bool) {
        let old = weekend ? baseline.answers.week.weekend : baseline.answers.week.weekday
        var week = draft.answers.week
        var day = weekend ? week.weekend : week.weekday
        if bound == .wake { day.wakeMinutes = old.wakeMinutes } else { day.sleepMinutes = old.sleepMinutes }
        // Відбій міг піти за межі «≥ 6 год після підйому» — та сама перевірка, що в кроці на 0.
        day = day.steppingWake(0).steppingSleep(0)
        if weekend { week.weekend = day } else { week.weekday = day }
        draft.answers.week = week
    }

    // MARK: - Нагадування

    var reminders: OnboardingReminders {
        _ = remindersRevision
        return services.onboardingReminders(postponed: remindersPostponed)
    }

    /// «Увімкнути»: головний вимикач і, якщо запиту ще не було, системний запит. Після відповіді — далі.
    func enableReminders() {
        services.profile.notificationsEnabled = true
        services.profiles.save()
        switch reminders {
        case .notAsked, .postponed:
            Task {
                await services.notifications.requestAuthorization()
                remindersRevision &+= 1
                next()
            }
        case .denied:
            openSystemSettings()
        case .granted, .disabledInApp:
            services.touch()
            remindersRevision &+= 1
            next()
        }
    }

    /// «Не зараз» — системний запит відкладається: шторка після першої порції спитає через 3 дні (SPEC-NOTIFICATIONS §16.5).
    func postponeReminders() {
        if reminders == .notAsked {
            services.notifications.postponePermissionPrompt(at: services.calendar.now)
            remindersPostponed = true
        }
        next()
    }

    func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Навігація

    func next() {
        confirmed.insert(step)
        move(by: 1)
    }

    func back() {
        move(by: -1)
    }

    private func move(by delta: Int) {
        let target = min(max(stepIndex + delta, 0), OnboardingCatalog.steps.count - 1)
        guard target != stepIndex else { return }
        movesForward = delta > 0
        withAnimation(WTAnimation.sheet) { stepIndex = target }
    }

    /// «Пропустити» першого запуску: на вітанні — нічого не змінюється, далі — «закінчити зараз» із підтвердженим (§6).
    func skip() {
        if confirmed.isEmpty {
            services.skipOnboarding()
        } else {
            services.applyOnboarding(draft, steps: confirmed, goal: goalMath, state: .skipped)
        }
        onExit(.home)
    }

    /// ✕ повторного проходу: без змін — одразу, зі змінами — спершу «Вийти без змін?» (§7.4).
    func close() {
        if draft == initialDraft || changes.isEmpty {
            onExit(.home)
        } else {
            withAnimation(WTAnimation.fade) { isConfirmingExit = true }
        }
    }

    func confirmExit() {
        isConfirmingExit = false
        onExit(.home)
    }

    func stay() {
        withAnimation(WTAnimation.fade) { isConfirmingExit = false }
    }

    /// Фініш першого запуску: записати все й піти на головний чи в «Перші кроки».
    func finish(_ exit: Exit = .home) {
        services.applyOnboarding(draft, steps: Set(OnboardingCatalog.questions), goal: goalMath, state: .completed)
        onExit(exit)
    }

    /// «Зберегти» повторного проходу. Без змін — просто закрити: «Готово» нічого не пише.
    func save() {
        if !changes.isEmpty {
            services.applyOnboarding(draft, steps: Set(OnboardingCatalog.questions), goal: goalMath, state: .completed)
        }
        onExit(.home)
    }
}
