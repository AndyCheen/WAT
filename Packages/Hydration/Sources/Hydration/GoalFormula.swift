import Foundation
import Core
import Persistence

/// Вхідні дані розрахунку денної норми.
public struct GoalInputs: Equatable, Sendable {
    public var weightKg: Double
    public var gender: Gender
    public var birthYear: Int?
    public var activity: ActivityLevel
    public var climate: ClimateLevel
    /// Вагітність чи годування (WAT-56). Лише при `gender == .female` — інакше ігнорується.
    public var condition: BodyCondition

    public init(
        weightKg: Double,
        gender: Gender = .unspecified,
        birthYear: Int? = nil,
        activity: ActivityLevel = .medium,
        climate: ClimateLevel = .moderate,
        condition: BodyCondition = .none
    ) {
        self.weightKg = weightKg
        self.gender = gender
        self.birthYear = birthYear
        self.activity = activity
        self.climate = climate
        self.condition = condition
    }

    /// Стан діє лише разом зі статтю «Жінка»: людина могла вибрати стан, а потім змінити стать.
    public var effectiveCondition: BodyCondition { gender == .female ? condition : .none }

    public func age(in year: Int) -> Int? {
        guard let birthYear, birthYear > 1900 else { return nil }
        return year - birthYear
    }
}

/// Формула норми винесена за протокол: у ТЗ і в макеті вони різні (PLAN.md §13.1),
/// тому фінальний вибір змінюється однією стрічкою, без правок UI.
public protocol GoalFormula: Sendable {
    var id: String { get }
    func dailyGoalMl(for inputs: GoalInputs, currentYear: Int) -> Int
    /// Складники норми до округлення — для «з чого вона складається» в онбордингу (WAT-56). Сума `ml`
    /// дорівнює нормі до округлення до 50 мл і меж `GoalRevision`.
    func breakdown(for inputs: GoalInputs, currentYear: Int) -> [GoalPart]
}

/// Один складник норми. `ml` від'ємний для віку: коефіцієнт зменшує частку від ваги.
public struct GoalPart: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Вага × мл на кілограм.
        case weight(mlPerKg: Double)
        /// Поправка віку до частки від ваги; `coefficient` — множник, `nil` — вік не вказано.
        case age(coefficient: Double, age: Int?)
        case activity(ActivityLevel)
        case climate(ClimateLevel)
        case condition(BodyCondition)
    }

    public let kind: Kind
    public let ml: Double

    public init(kind: Kind, ml: Double) {
        self.kind = kind
        self.ml = ml
    }
}

public extension GoalFormula {
    /// Норму завжди округлюємо до 50 мл і тримаємо в допустимих межах.
    func normalize(_ raw: Double) -> Int {
        GoalRevision.clamp(Int((raw / 50).rounded()) * 50)
    }
}

/// Формула з ТЗ §3: `(маса × K_стать × K_вік) + бонус активності`.
public struct SpecGoalFormula: GoalFormula {
    public let id = "spec"
    public init() {}

    /// мл на кг маси
    static func genderCoefficient(_ gender: Gender) -> Double {
        switch gender {
        case .male: return 35
        case .female: return 30
        case .unspecified: return 32.5
        }
    }

    static func ageCoefficient(age: Int?) -> Double {
        guard let age else { return 0.97 }
        switch age {
        case ..<31: return 1.0
        case 31...55: return 0.95
        default: return 0.90
        }
    }

    static func activityBonusMl(_ level: ActivityLevel) -> Double {
        switch level {
        case .low: return 200
        case .medium: return 350
        case .high: return 500
        }
    }

    static func climateBonusMl(_ level: ClimateLevel) -> Double {
        switch level {
        case .moderate: return 0
        case .hot: return 400
        }
    }

    /// EFSA 2010 (SPEC-ONBOARDING §5, §13): вагітність +300 мл, годування груддю +700 мл на добу.
    /// Чернетка: фактчек і остаточні числа — WAT-57.
    static func conditionBonusMl(_ condition: BodyCondition) -> Double {
        switch condition {
        case .none: return 0
        case .pregnancy: return 300
        case .breastfeeding: return 700
        }
    }

    // Не сума `breakdown`: «вага + (вага × K − вага)» у плаваючій комі на межі округлення до 50 мл
    // давало б інше число, ніж ця формула з ТЗ. Розклад — лише для показу.
    public func dailyGoalMl(for inputs: GoalInputs, currentYear: Int) -> Int {
        let base = inputs.weightKg
            * Self.genderCoefficient(inputs.gender)
            * Self.ageCoefficient(age: inputs.age(in: currentYear))
        return normalize(base + Self.activityBonusMl(inputs.activity) + Self.climateBonusMl(inputs.climate)
                         + Self.conditionBonusMl(inputs.effectiveCondition))
    }

    public func breakdown(for inputs: GoalInputs, currentYear: Int) -> [GoalPart] {
        let mlPerKg = Self.genderCoefficient(inputs.gender)
        let age = inputs.age(in: currentYear)
        let coefficient = Self.ageCoefficient(age: age)
        let weight = inputs.weightKg * mlPerKg
        var parts = [
            GoalPart(kind: .weight(mlPerKg: mlPerKg), ml: weight),
            GoalPart(kind: .age(coefficient: coefficient, age: age), ml: weight * coefficient - weight),
            GoalPart(kind: .activity(inputs.activity), ml: Self.activityBonusMl(inputs.activity)),
        ]
        if inputs.climate != .moderate {
            parts.append(GoalPart(kind: .climate(inputs.climate), ml: Self.climateBonusMl(inputs.climate)))
        }
        if inputs.effectiveCondition != .none {
            parts.append(GoalPart(kind: .condition(inputs.effectiveCondition), ml: Self.conditionBonusMl(inputs.effectiveCondition)))
        }
        return parts
    }
}

/// Формула з макета 4a: `вага × 30 + бонус активності + бонус клімату`.
/// Не питає стать і вік — залишена для точного відтворення поведінки макета.
public struct MockupGoalFormula: GoalFormula {
    public let id = "mockup"
    public init() {}

    public func dailyGoalMl(for inputs: GoalInputs, currentYear: Int) -> Int {
        let activityBonus = [0.0, 350.0, 700.0][inputs.activity.rawValue]
        let climateBonus = [0.0, 400.0][inputs.climate.rawValue]
        return normalize(inputs.weightKg * 30 + activityBonus + climateBonus)
    }

    public func breakdown(for inputs: GoalInputs, currentYear: Int) -> [GoalPart] {
        [
            GoalPart(kind: .weight(mlPerKg: 30), ml: inputs.weightKg * 30),
            GoalPart(kind: .activity(inputs.activity), ml: [0.0, 350.0, 700.0][inputs.activity.rawValue]),
            GoalPart(kind: .climate(inputs.climate), ml: [0.0, 400.0][inputs.climate.rawValue]),
        ]
    }
}

public enum GoalFormulaRegistry {
    /// Поточний вибір. Змінюється після відповіді на питання PLAN.md §13.1.
    public static let current: GoalFormula = SpecGoalFormula()
    public static let all: [GoalFormula] = [SpecGoalFormula(), MockupGoalFormula()]
}
