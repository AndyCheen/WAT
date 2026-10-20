import Foundation
import Core
import Persistence
import Hydration

/// Тексти онбордингу (WAT-56, SPEC-ONBOARDING §3) — чиста функція, як `SchedulePresenter` і `LearnPresenter`.
///
/// На «ти», без роду й без минулого часу (SPEC-NOTIFICATIONS §14.1). Тексти чорнові: редактуру й фактчек
/// застережень доводить WAT-57.
enum OnboardingPresenter {

    // MARK: - Заголовки кроків

    struct Header: Equatable {
        let title: String
        let subtitle: String?
    }

    static func header(_ step: OnboardingStep, mode: OnboardingMode, offersGoalChoice: Bool, reminders: OnboardingReminders) -> Header {
        switch step {
        case .hello:
            return mode == .firstRun
                ? Header(title: "Привіт! Налаштуймо застосунок під тебе",
                         subtitle: "\(OnboardingCatalog.questions.count) коротких питань — і в тебе своя норма, свій день і нагадування без зайвого. Це хвилина.")
                : Header(title: "Перевіримо налаштування",
                         subtitle: "Усе, що вже є, підставлено з позначкою «Зараз». Змінюй лише те, що треба — збережеться після «Зберегти».")
        case .units:
            return Header(title: "У чому рахувати?", subtitle: "Одиниці для води, ваги й часу")
        case .gender:
            return Header(title: "Вкажи стать", subtitle: "Лише для розрахунку норми — тексти від цього не залежать")
        case .age:
            return Header(title: "Скільки тобі років?", subtitle: "Після 30 і після 55 норма трохи менша")
        case .weight:
            return Header(title: "Скільки ти важиш?", subtitle: "Від ваги норма залежить найбільше")
        case .activity:
            return Header(title: "Скільки руху в звичайному дні?", subtitle: "Тренування й робота на ногах додають до норми")
        case .goal:
            if mode == .firstRun {
                return Header(title: "Твоя норма", subtitle: "Порахована з твоїх відповідей — можна підправити")
            }
            return Header(title: "Норма", subtitle: offersGoalChoice
                          ? "Розрахунок дає інше число, ніж зараз. Обери, яку норму лишити"
                          : "Розрахунок збігається з поточною нормою")
        case .day:
            return Header(title: "Коли починається й закінчується твій день?", subtitle: "Нагадування приходять лише в ці години")
        case .rhythm:
            return Header(title: "Як тобі зручніше?", subtitle: "Змінити можна будь-коли в налаштуваннях")
        case .glass:
            return Header(title: "Скільки в твоїй склянці?", subtitle: "Кнопка «+склянка» в нагадуванні додаватиме стільки")
        case .reminders:
            switch reminders {
            case .granted:
                return Header(title: "Нагадування увімкнені", subtitle: remindersPitch)
            case .denied:
                return Header(title: "Сповіщення вимкнені в налаштуваннях iPhone",
                              subtitle: "Увімкнути їх можна там — нагадування з'являться одразу")
            case .notAsked, .disabledInApp, .postponed:
                return Header(title: "Нагадувати, коли забудеш про воду?", subtitle: remindersPitch)
            }
        case .done:
            return Header(title: "", subtitle: nil)
        }
    }

    static let remindersPitch = "Лише коли відстаєш від свого темпу — хто п'є рівномірно, нагадувань не отримує"

    /// «Норма · 2 / 5» над заголовком.
    static func stepLabel(_ step: OnboardingStep) -> String? {
        guard let chapter = step.chapter else { return nil }
        let steps = OnboardingCatalog.steps(in: chapter)
        guard let index = steps.firstIndex(of: step) else { return nil }
        // Розділ з одного кроку — без «1 / 1».
        guard steps.count > 1 else { return chapter.title.uppercased() }
        return "\(chapter.title.uppercased()) · \(index + 1) / \(steps.count)"
    }

    // MARK: - Застереження (рішення від 19.10.2026; остаточні тексти й фактчек — WAT-57)

    static let conditionDisclaimer =
        "Орієнтир за рекомендаціями EFSA, а не медична порада. Під час вагітності й годування погодь свою норму з лікарем."
    static let goalDisclaimer =
        "Розрахунок орієнтовний і не є медичною порадою. Якщо маєш захворювання чи особливий стан — порадься з лікарем."

    // MARK: - Варіанти

    struct Option<Value: Equatable>: Equatable {
        let value: Value
        let id: String
        let title: String
        let subtitle: String?
        let glyph: String?

        init(_ value: Value, id: String, title: String, subtitle: String? = nil, glyph: String? = nil) {
            self.value = value
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.glyph = glyph
        }
    }

    static let genderOptions: [Option<Gender>] = [
        Option(.male, id: "male", title: "Чоловік"),
        Option(.female, id: "female", title: "Жінка"),
        Option(.unspecified, id: "unspecified", title: "Не вказувати"),
    ]
    static let conditionQuestion = "Зараз щось із цього?"
    static let conditionOptions: [Option<BodyCondition>] = [
        Option(.none, id: "none", title: "Ні"),
        Option(.pregnancy, id: "pregnancy", title: "Вагітність"),
        Option(.breastfeeding, id: "breastfeeding", title: "Годування груддю"),
    ]
    static let activityOptions: [Option<ActivityLevel>] = [
        Option(.low, id: "low", title: "Мало руху", subtitle: "Сидяча робота, мало ходиш", glyph: "🪑"),
        Option(.medium, id: "medium", title: "Помірно", subtitle: "Прогулянки, 1–3 тренування на тиждень", glyph: "🚶"),
        Option(.high, id: "high", title: "Багато", subtitle: "Фізична робота чи тренування майже щодня", glyph: "🏃"),
    ]
    static let rhythmOptions: [Option<Bool>] = [
        Option(true, id: "parts", title: "Ранок, день і вечір", subtitle: "Три цілі за день — легше не відкладати все на вечір"),
        Option(false, id: "day", title: "Просто норма за день", subtitle: "Без цілей на ранок, день і вечір — лише денна норма"),
    ]
    static let intervalsNote = "🔔 Нагадування підуть рівними інтервалами"

    static func goalOptions(baseline: OnboardingBaseline) -> [Option<OnboardingGoalChoice>] {
        let current: String
        switch baseline.goalSource {
        case .manual: current = "Задано вручну"
        case .calculated: current = "Розраховано раніше"
        case .onboarding, .seed: current = "Типова"
        }
        return [
            Option(.keepCurrent, id: "keep", title: "Залишити поточну", subtitle: current),
            Option(.calculated, id: "calculated", title: "Взяти розраховану", subtitle: "Вага, вік і активність"),
        ]
    }

    static let ageNotSpecified = "Не вказувати"
    static let goalAdjustTitle = "Підправити"
    /// Під вагою першого запуску, поки людина її не змінила: 70 кг — підставлене, а не її відповідь.
    static let typicalHint = "Типове значення — зміни на своє"

    /// Поправка норми: «0 мл», «+50 мл», «−100 мл».
    static func adjustLabel(_ ml: Int, _ unit: VolumeUnit) -> String {
        ml == 0 ? volume(0, unit) : "\(ml > 0 ? "+" : "−")\(volume(abs(ml), unit))"
    }

    // MARK: - Одиниці

    struct UnitRow: Equatable {
        let id: String
        let title: String
        let options: [String]
    }

    static let unitRows: [UnitRow] = [
        UnitRow(id: "volume", title: "Об'єм", options: VolumeUnit.allCases.map(volumeUnitTitle)),
        UnitRow(id: "mass", title: "Вага", options: MassUnit.allCases.map(massUnitTitle)),
        UnitRow(id: "time", title: "Час", options: TimeFormat.allCases.map(timeFormatTitle)),
    ]

    static func volumeUnitTitle(_ unit: VolumeUnit) -> String {
        unit == .milliliters ? "Мілілітри" : "Унції"
    }

    static func massUnitTitle(_ unit: MassUnit) -> String {
        unit == .kilograms ? "Кілограми" : "Фунти"
    }

    static func timeFormatTitle(_ format: TimeFormat) -> String {
        format == .hours24 ? "24 години" : "12 годин"
    }

    // MARK: - Значення

    /// «250 мл» / «8 унц.» — «унц.» кирилицею, як погоджено в WAT-46.
    static func volume(_ ml: Int, _ unit: VolumeUnit) -> String {
        unit == .milliliters ? "\(ml) мл" : "\(Volume.display(ml, in: .fluidOunces)) унц."
    }

    /// Норма великим числом і одиницею окремо: «2.55» + «л», «86» + «унц.».
    static func goalParts(_ ml: Int, _ unit: VolumeUnit) -> (number: String, unit: String) {
        unit == .milliliters
            ? (Volume.litersLabel(ml, fractionDigits: ml % 100 == 0 ? 1 : 2), "л")
            : ("\(Volume.display(ml, in: .fluidOunces))", "унц.")
    }

    static func goal(_ ml: Int, _ unit: VolumeUnit) -> String {
        let parts = goalParts(ml, unit)
        return "\(parts.number) \(parts.unit)"
    }

    static func weightNumber(_ kg: Double, _ unit: MassUnit) -> Int {
        Mass.display(kg, in: unit)
    }

    static func weightUnit(_ value: Int, _ unit: MassUnit) -> String {
        unit == .kilograms ? "кг" : Plural.uk(value, one: "фунт", few: "фунти", many: "фунтів")
    }

    static func weight(_ kg: Double, _ unit: MassUnit) -> String {
        let value = weightNumber(kg, unit)
        return "\(value) \(weightUnit(value, unit))"
    }

    /// Межі лінійки ваги в одиницях людини.
    static func weightRange(_ unit: MassUnit) -> ClosedRange<Int> {
        let range = OnboardingAnswers.weightRangeKg
        return Mass.display(range.lowerBound, in: unit)...Mass.display(range.upperBound, in: unit)
    }

    static func ageValue(_ age: Int?) -> String {
        age.map { "\($0)" } ?? "не вказано"
    }

    static func genderValue(_ gender: Gender) -> String {
        switch gender {
        case .male: return "чоловік"
        case .female: return "жінка"
        case .unspecified: return "не вказано"
        }
    }

    static func conditionValue(_ condition: BodyCondition) -> String {
        switch condition {
        case .none: return "немає"
        case .pregnancy: return "вагітність"
        case .breastfeeding: return "годування груддю"
        }
    }

    static func activityValue(_ level: ActivityLevel) -> String {
        switch level {
        case .low: return "мало руху"
        case .medium: return "помірно"
        case .high: return "багато"
        }
    }

    static func rhythmValue(_ enabled: Bool) -> String {
        enabled ? "ранок, день і вечір" : "просто норма"
    }

    static func clock(_ minutes: Int, _ format: TimeFormat) -> String {
        format.clock(minutes)
    }

    static func range(_ day: DaySchedule, _ format: TimeFormat) -> String {
        "\(format.clock(day.wakeMinutes))–\(format.clock(day.sleepMinutes))"
    }

    static func weekendValue(_ week: WeekSchedule, _ format: TimeFormat) -> String {
        week.weekendEnabled ? range(week.weekend, format) : "як будні"
    }

    // MARK: - Розклад норми

    struct PartRow: Equatable, Identifiable {
        enum Tone: Equatable { case weight, age, activity, extra }
        let id: String
        let tone: Tone
        let title: String
        let value: String
        /// Частка смуги — лише додатні складники.
        let ml: Double
    }

    static func partRows(_ parts: [GoalPart], answers: OnboardingAnswers) -> [PartRow] {
        parts.compactMap { part in
            let signed = Int(part.ml.rounded())
            let value = signed < 0 ? "−\(volume(-signed, answers.volumeUnit))" : "+\(volume(signed, answers.volumeUnit))"
            switch part.kind {
            case .weight(let mlPerKg):
                return PartRow(id: "weight", tone: .weight, title: "Вага \(weight(answers.weightKg, .kilograms)) × \(number(mlPerKg)) мл",
                               value: volume(signed, answers.volumeUnit), ml: part.ml)
            case .age(let coefficient, let age):
                guard coefficient != 1 else { return nil }
                return PartRow(id: "age", tone: .age, title: "Вік \(ageValue(age)) · ×\(number(coefficient))", value: value, ml: 0)
            case .activity(let level):
                return PartRow(id: "activity", tone: .activity, title: "Активність — \(activityValue(level))", value: value, ml: part.ml)
            case .climate:
                return PartRow(id: "climate", tone: .extra, title: "Спека", value: value, ml: part.ml)
            case .condition(let condition):
                return PartRow(id: "condition", tone: .extra, title: conditionValue(condition).capitalizedFirst, value: value, ml: part.ml)
            }
        }
    }

    /// «32.5», «0.95», «35» — без зайвих нулів.
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%g", value)
    }

    // MARK: - Сцени («Сцена», SPEC-ONBOARDING §10)

    static func mlPerKg(_ answers: OnboardingAnswers) -> String {
        number(FormulaCoefficients.mlPerKg(answers.gender))
    }

    static let mlPerKgCaption = "на кожен кілограм ваги"

    static func conditionBadge(_ condition: BodyCondition, _ unit: VolumeUnit) -> String? {
        switch condition {
        case .none: return nil
        case .pregnancy: return "+\(volume(300, unit)) · вагітність"
        case .breastfeeding: return "+\(volume(700, unit)) · годування груддю"
        }
    }

    static func ageCoefficient(_ age: Int?) -> String {
        "×\(number(FormulaCoefficients.age(age)))"
    }

    static let ageCaption = "коефіцієнт віку"

    /// Відрізки шкали віку з межами коефіцієнтів `SpecGoalFormula` (`ageCoefficient`).
    static let ageSegments: [(range: ClosedRange<Int>, label: String)] = [
        (14...30, "×1.0"), (31...55, "×0.95"), (56...99, "×0.9"),
    ]

    static func weightFormula(_ answers: OnboardingAnswers) -> String {
        let kg = Int(answers.weightKg.rounded())
        let mlPerKg = FormulaCoefficients.mlPerKg(answers.gender)
        return "\(kg) кг × \(number(mlPerKg)) мл = \(volume(Int((answers.weightKg * mlPerKg).rounded()), answers.volumeUnit))"
    }

    static func activityBonus(_ level: ActivityLevel, _ unit: VolumeUnit) -> String {
        "+\(volume(Int(FormulaCoefficients.activity(level)), unit)) до норми"
    }

    /// `blocks` — скільки блоків цілей дає розклад (`PaceCurve.goalBlocks()`), а не «3» з тексту.
    static func rhythmScene(_ enabled: Bool, blocks: Int) -> (title: String, caption: String) {
        enabled ? ("\(blocks) \(Plural.uk(blocks, one: "ціль", few: "цілі", many: "цілей"))", "ранок, день і вечір")
                : ("1 ціль", "лише денна норма")
    }

    static let goalCaption = "на день"
    static let unitsSampleCaption = "так виглядатимуть числа"

    /// Зразок у сцені кроку «Одиниці»: склянка, вага й підйом у вибраних одиницях.
    static func unitsSample(_ answers: OnboardingAnswers) -> [(glyph: String, text: String)] {
        [("💧", volume(answers.glassMl, answers.volumeUnit)),
         ("⚖️", weight(answers.weightKg, answers.massUnit)),
         ("☀️", clock(answers.week.weekday.wakeMinutes, answers.timeFormat))]
    }

    static func changesCount(_ count: Int) -> String {
        count == 0 ? "без змін" : Plural.uk(count, one: "зміна", few: "зміни", many: "змін")
    }

    // MARK: - Нагадування на екрані блокування

    static let lockTime = "10:41"
    static let lockDate = "понеділок, 19 жовтня"
    static let previewTitle = "💧 Вода чекає"
    /// Текст варіанта «💧 Вода чекає» з `NotificationCopy`; залишок — у одиницях людини.
    static func previewBody(_ answers: OnboardingAnswers) -> String {
        "До цілі ще \(goal(1200, answers.volumeUnit)). Почни з однієї склянки"
    }

    static func previewActions(_ answers: OnboardingAnswers) -> [String] {
        ["+\(volume(answers.glassMl, answers.volumeUnit))", "Нагадати за годину"]
    }

    // MARK: - Фініш

    static let doneTitle = "Усе готово"
    static let doneSubtitle = "Змінити можна будь-коли в «Налаштуваннях»"
    static let changesTitle = "Що зміниться"
    static let changesSubtitle = "Збережеться лише після «Зберегти»"
    static let noChangesTitle = "Без змін"
    static let noChangesSubtitle = "Усе лишається як було"
    static let restUnchanged = "Решта — без змін"

    struct SummaryRow: Equatable, Identifiable {
        let id: String
        let glyph: String
        let title: String
        let value: String
        let detail: String?
    }

    static func summary(_ answers: OnboardingAnswers, goalMl: Int, reminders: OnboardingReminders) -> [SummaryRow] {
        [
            SummaryRow(id: "goal", glyph: "🎯", title: "Норма", value: "\(goal(goalMl, answers.volumeUnit)) на день", detail: nil),
            SummaryRow(id: "day", glyph: "☀️", title: "День", value: range(answers.week.weekday, answers.timeFormat),
                       detail: answers.week.weekendEnabled ? "вихідні \(range(answers.week.weekend, answers.timeFormat))" : nil),
            SummaryRow(id: "rhythm", glyph: "⏱", title: "Ритм", value: rhythmValue(answers.dayRhythm), detail: nil),
            SummaryRow(id: "glass", glyph: "🥛", title: "Склянка", value: volume(answers.glassMl, answers.volumeUnit), detail: nil),
            SummaryRow(id: "reminders", glyph: "🔔", title: "Нагадування", value: remindersValue(reminders), detail: nil),
        ]
    }

    /// Поточні налаштування на вітанні повторного проходу.
    static func current(_ baseline: OnboardingBaseline, reminders: OnboardingReminders) -> [SummaryRow] {
        let answers = baseline.answers
        return [
            SummaryRow(id: "goal", glyph: "🎯", title: "Норма", value: goal(baseline.goalMl, answers.volumeUnit),
                       detail: baseline.goalSource == .manual ? "вручну" : nil),
            SummaryRow(id: "day", glyph: "☀️", title: "День", value: range(answers.week.weekday, answers.timeFormat),
                       detail: answers.week.weekendEnabled ? "вихідні \(range(answers.week.weekend, answers.timeFormat))" : nil),
            SummaryRow(id: "rhythm", glyph: "⏱", title: "Ритм", value: rhythmValue(answers.dayRhythm), detail: nil),
            SummaryRow(id: "glass", glyph: "🥛", title: "Склянка", value: volume(answers.glassMl, answers.volumeUnit), detail: nil),
            SummaryRow(id: "reminders", glyph: "🔔", title: "Нагадування", value: remindersValue(reminders), detail: nil),
        ]
    }

    static func remindersValue(_ reminders: OnboardingReminders) -> String {
        switch reminders {
        case .granted: return "увімкнені"
        case .denied: return "вимкнені в iOS"
        case .disabledInApp: return "вимкнені"
        case .notAsked, .postponed: return "спитаємо після першої порції"
        }
    }

    // MARK: - Кнопки й діалоги

    static let next = "Далі"
    static let start = "Почати"
    static let skip = "Пропустити"
    static let notNow = "Не зараз"
    static let acceptGoal = "Підходить"
    static let enable = "Увімкнути"
    static let openSettings = "Відкрити налаштування"
    static let finish = "До першої склянки"
    static let howTo = "Як користуватися"
    static let save = "Зберегти"
    static let cancel = "Скасувати"
    static let ready = "Готово"
    static let nowBadge = "Зараз"
    static let typicalBadge = "Типово"
    static let wasPrefix = "Було"
    static let revert = "Як було"
    static let exitTitle = "Вийти без змін?"
    static let exitMessage = "Зміни не збережуться — усе лишиться як було."
    static let exitConfirm = "Вийти"
    static let exitStay = "Залишитись"
}

/// Стан дозволу на кроці «Нагадування» (§3.1): системний запит iOS показує лише раз, тож крок відображає
/// те, що є, а не питає наосліп.
public enum OnboardingReminders: Equatable, Sendable {
    /// Системного запиту ще не було.
    case notAsked
    /// «Не зараз» на цьому кроці — шторка після першої порції спитає через 3 дні.
    case postponed
    case granted
    /// Дозвіл є, але вимкнено головний вимикач у застосунку — «Увімкнути» вмикає його без запиту.
    case disabledInApp
    case denied
}

/// Коефіцієнти поточної формули для підписів сцен: та сама формула, а не копія чисел у тексті.
enum FormulaCoefficients {
    static func mlPerKg(_ gender: Gender) -> Double {
        part(GoalInputs(weightKg: 1, gender: gender)) { if case .weight(let k) = $0 { return k } else { return nil } } ?? 0
    }

    static func age(_ age: Int?) -> Double {
        let inputs = GoalInputs(weightKg: 1, birthYear: age.map { 2000 - $0 })
        return part(inputs, year: 2000) { if case .age(let k, _) = $0 { return k } else { return nil } } ?? 1
    }

    static func activity(_ level: ActivityLevel) -> Double {
        let inputs = GoalInputs(weightKg: 1, activity: level)
        return GoalFormulaRegistry.current.breakdown(for: inputs, currentYear: 2000)
            .first { if case .activity = $0.kind { return true } else { return false } }?.ml ?? 0
    }

    private static func part(_ inputs: GoalInputs, year: Int = 2000, _ pick: (GoalPart.Kind) -> Double?) -> Double? {
        GoalFormulaRegistry.current.breakdown(for: inputs, currentYear: year).compactMap { pick($0.kind) }.first
    }
}
