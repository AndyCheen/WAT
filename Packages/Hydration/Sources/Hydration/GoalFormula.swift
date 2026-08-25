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

    public init(
        weightKg: Double,
        gender: Gender = .unspecified,
        birthYear: Int? = nil,
        activity: ActivityLevel = .medium,
        climate: ClimateLevel = .moderate
    ) {
        self.weightKg = weightKg
        self.gender = gender
        self.birthYear = birthYear
        self.activity = activity
        self.climate = climate
    }

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

    public func dailyGoalMl(for inputs: GoalInputs, currentYear: Int) -> Int {
        let base = inputs.weightKg
            * Self.genderCoefficient(inputs.gender)
            * Self.ageCoefficient(age: inputs.age(in: currentYear))
        return normalize(base + Self.activityBonusMl(inputs.activity) + Self.climateBonusMl(inputs.climate))
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
}

public enum GoalFormulaRegistry {
    /// Поточний вибір. Змінюється після відповіді на питання PLAN.md §13.1.
    public static let current: GoalFormula = SpecGoalFormula()
    public static let all: [GoalFormula] = [SpecGoalFormula(), MockupGoalFormula()]
}
