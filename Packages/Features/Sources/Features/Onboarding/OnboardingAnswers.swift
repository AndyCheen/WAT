import Foundation
import Core
import Persistence
import Hydration

/// Відповіді онбордингу — значення, без SwiftData: чернетку можна міняти й кидати, нічого не записавши (SPEC-ONBOARDING §7).
/// Внутрішньо все в мл, кг і хвилинах; одиниці людини — лише на межі UI, як і по всьому застосунку.
public struct OnboardingAnswers: Equatable, Sendable {
    public var volumeUnit: VolumeUnit = .milliliters
    public var massUnit: MassUnit = .kilograms
    public var timeFormat: TimeFormat = .hours24
    public var gender: Gender = .unspecified
    public var condition: BodyCondition = .none
    /// `nil` — «Не вказувати»: формула бере середній коефіцієнт.
    public var age: Int?
    public var weightKg: Double = Self.typicalWeightKg
    public var activity: ActivityLevel = .medium
    public var week = WeekSchedule(
        weekday: .weekdayDefault, weekendEnabled: false, weekend: DaySchedule(wakeMinutes: 9 * 60, sleepMinutes: 23 * 60)
    )
    public var dayRhythm = true
    public var glassMl = 250

    public init() {}

    /// Типова вага — лише підставлене значення, а не відповідь людини (§3.1): на кроці «Норма» видно, з якої ваги
    /// пораховано, а в повторному проході вона позначена «Типово».
    static let typicalWeightKg = 70.0
    /// З 14 років EFSA рахує норму води як для дорослих (§3.1).
    static let ageRange = 14...99
    static let typicalAge = 30
    static let weightRangeKg = 30.0...200.0
    static let glassChoicesMl = [200, 250, 300, 350, 400]

    /// Стан має сенс лише при статі «Жінка» — інакше він лишився б від попередньої відповіді.
    var effectiveCondition: BodyCondition { gender == .female ? condition : .none }

    func goalInputs(currentYear: Int, climate: ClimateLevel) -> GoalInputs {
        GoalInputs(weightKg: weightKg, gender: gender, birthYear: age.map { currentYear - $0 }, activity: activity,
                   climate: climate, condition: effectiveCondition)
    }

    /// Те, від чого залежить формула: зміна будь-чого з цього скидає поправку норми ±50 мл (§3.1).
    var formulaInputs: [Double] {
        [Double(gender.rawValue), Double(effectiveCondition.rawValue), Double(age ?? -1), weightKg, Double(activity.rawValue)]
    }
}

/// Що зараз у застосунку — «Зараз» на кроках і «було» на фініші повторного проходу (§7.2). На першому запуску це
/// типові значення профілю.
public struct OnboardingBaseline: Equatable, Sendable {
    public var answers: OnboardingAnswers
    public var goalMl: Int
    /// Як з'явилась поточна норма: ручну мовчки не переписуємо (§7.3).
    public var goalSource: GoalSource
    /// Вагу в профілі ще не вказували — у повторному проході вона «Типово», а не «Зараз».
    public var weightKnown: Bool
    public var reminderMode: ReminderMode
    public var currentYear: Int
    /// Клімат онбординг не питає (§4), але формула його враховує.
    public var climate: ClimateLevel

    public init(answers: OnboardingAnswers, goalMl: Int, goalSource: GoalSource, weightKnown: Bool,
                reminderMode: ReminderMode, currentYear: Int, climate: ClimateLevel) {
        self.answers = answers
        self.goalMl = goalMl
        self.goalSource = goalSource
        self.weightKnown = weightKnown
        self.reminderMode = reminderMode
        self.currentYear = currentYear
        self.climate = climate
    }
}

/// Яку норму лишити, коли розрахунок дає інше число, ніж зараз (§7.3).
public enum OnboardingGoalChoice: String, Equatable, Sendable {
    case keepCurrent, calculated
}

/// Чернетка: відповіді плюс рішення про норму. Записується одним проходом (`AppServices.applyOnboarding`).
public struct OnboardingDraft: Equatable, Sendable {
    public var answers: OnboardingAnswers {
        didSet {
            // Поправка — відносно розрахунку: нові вхідні дані дають нове число, стара поправка до нього не стосується.
            if answers.formulaInputs != oldValue.formulaInputs { goalAdjustMl = 0 }
        }
    }
    public var goalChoice: OnboardingGoalChoice
    public var goalAdjustMl = 0

    public init(answers: OnboardingAnswers, goalChoice: OnboardingGoalChoice) {
        self.answers = answers
        self.goalChoice = goalChoice
    }
}

/// Норма з чернетки — чиста функція, однакова для екрана, фінішу й запису.
struct OnboardingGoal {
    let baseline: OnboardingBaseline
    let formula: GoalFormula

    init(baseline: OnboardingBaseline, formula: GoalFormula = GoalFormulaRegistry.current) {
        self.baseline = baseline
        self.formula = formula
    }

    func calculated(_ answers: OnboardingAnswers) -> Int {
        formula.dailyGoalMl(for: answers.goalInputs(currentYear: baseline.currentYear, climate: baseline.climate),
                            currentYear: baseline.currentYear)
    }

    func parts(_ answers: OnboardingAnswers) -> [GoalPart] {
        formula.breakdown(for: answers.goalInputs(currentYear: baseline.currentYear, climate: baseline.climate),
                          currentYear: baseline.currentYear)
    }

    /// Розрахована з поправкою — у межах `GoalRevision`.
    func adjusted(_ draft: OnboardingDraft) -> Int {
        GoalRevision.clamp(calculated(draft.answers) + draft.goalAdjustMl)
    }

    func final(_ draft: OnboardingDraft) -> Int {
        draft.goalChoice == .keepCurrent ? baseline.goalMl : adjusted(draft)
    }

    /// Вибір «залишити / взяти» з'являється, лише коли числа різні.
    func offersChoice(_ draft: OnboardingDraft, mode: OnboardingMode) -> Bool {
        mode == .revisit && calculated(draft.answers) != baseline.goalMl
    }

    /// Типовий вибір: ручну норму — залишити, типову чи розраховану — замінити новою (§7.3).
    static func defaultChoice(baseline: OnboardingBaseline, calculated: Int, mode: OnboardingMode) -> OnboardingGoalChoice {
        mode == .revisit && baseline.goalSource == .manual && calculated != baseline.goalMl ? .keepCurrent : .calculated
    }
}

/// Перший запуск чи повторний прохід із «Налаштувань» (§6, §7).
public enum OnboardingMode: Equatable, Sendable {
    case firstRun, revisit
}

/// Рядок «Що зміниться» на фініші повторного проходу (§7.4).
struct OnboardingChange: Equatable, Identifiable {
    let id: String
    let glyph: String
    let title: String
    let old: String
    let new: String
}

enum OnboardingChanges {
    /// Лише змінене, у порядку кроків. Старе значення — в старих одиницях, нове — в нових: «78 кг → 172 фунти».
    static func list(baseline: OnboardingBaseline, draft: OnboardingDraft, goal: OnboardingGoal) -> [OnboardingChange] {
        let old = baseline.answers, new = draft.answers
        typealias P = OnboardingPresenter
        var changes: [OnboardingChange] = []
        func add(_ id: String, _ glyph: String, _ title: String, _ from: String, _ to: String) {
            if from != to { changes.append(OnboardingChange(id: id, glyph: glyph, title: title, old: from, new: to)) }
        }

        add("volumeUnit", "📏", "Об'єм", P.volumeUnitTitle(old.volumeUnit), P.volumeUnitTitle(new.volumeUnit))
        add("massUnit", "📏", "Вага в", P.massUnitTitle(old.massUnit), P.massUnitTitle(new.massUnit))
        add("timeFormat", "🕐", "Час", P.timeFormatTitle(old.timeFormat), P.timeFormatTitle(new.timeFormat))
        let finalGoal = goal.final(draft)
        if finalGoal != baseline.goalMl {
            add("goal", "🎯", "Норма", P.goal(baseline.goalMl, old.volumeUnit), P.goal(finalGoal, new.volumeUnit))
        }
        if abs(old.weightKg - new.weightKg) >= 0.05 || old.massUnit != new.massUnit {
            add("weight", "⚖️", "Вага", P.weight(old.weightKg, old.massUnit), P.weight(new.weightKg, new.massUnit))
        }
        add("age", "🎂", "Вік", P.ageValue(old.age), P.ageValue(new.age))
        add("gender", "👤", "Стать", P.genderValue(old.gender), P.genderValue(new.gender))
        add("condition", "🤰", "Особливий стан", P.conditionValue(old.effectiveCondition), P.conditionValue(new.effectiveCondition))
        add("activity", "🏃", "Активність", P.activityValue(old.activity), P.activityValue(new.activity))
        add("weekday", "☀️", "День", P.range(old.week.weekday, old.timeFormat), P.range(new.week.weekday, new.timeFormat))
        add("weekend", "🗓", "Вихідні", P.weekendValue(old.week, old.timeFormat), P.weekendValue(new.week, new.timeFormat))
        add("rhythm", "⏱", "Ритм дня", P.rhythmValue(old.dayRhythm), P.rhythmValue(new.dayRhythm))
        if switchesToIntervals(baseline: baseline, draft: draft) {
            add("reminderMode", "🔔", "Нагадування", "за темпом", "рівні інтервали")
        }
        add("glass", "🥛", "Склянка", P.volume(old.glassMl, old.volumeUnit), P.volume(new.glassMl, new.volumeUnit))
        return changes
    }

    /// «Просто норма» переводить нагадування «за темпом» на рівні інтервали (SPEC-NOTIFICATIONS §21, §28) — і це
    /// видно в переліку, а не стається мовчки.
    static func switchesToIntervals(baseline: OnboardingBaseline, draft: OnboardingDraft) -> Bool {
        !draft.answers.dayRhythm && baseline.answers.dayRhythm && baseline.reminderMode == .pace
    }
}
