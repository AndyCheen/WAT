import Foundation

/// Одиниці об'єму. ТЗ §1: «обидві з перемиканням».
/// Внутрішньо все зберігається в мілілітрах — конвертація лише на межі UI.
public enum VolumeUnit: Int, Codable, CaseIterable, Sendable {
    case milliliters = 0
    case fluidOunces = 1

    public var shortTitle: String {
        switch self {
        case .milliliters: return "мл"
        case .fluidOunces: return "fl oz"
        }
    }

    public var largeTitle: String {
        switch self {
        case .milliliters: return "л"
        case .fluidOunces: return "fl oz"
        }
    }
}

public enum Volume {
    public static let mlPerFlOz = 29.5735

    public static func display(_ ml: Int, in unit: VolumeUnit) -> Int {
        switch unit {
        case .milliliters: return ml
        case .fluidOunces: return Int((Double(ml) / mlPerFlOz).rounded())
        }
    }

    public static func toMilliliters(_ value: Int, from unit: VolumeUnit) -> Int {
        switch unit {
        case .milliliters: return value
        case .fluidOunces: return Int((Double(value) * mlPerFlOz).rounded())
        }
    }

    /// «1.25» для 1250 мл — формат великого показника на кільці (макет 1a).
    public static func litersLabel(_ ml: Int, fractionDigits: Int = 2) -> String {
        String(format: "%.\(fractionDigits)f", Double(ml) / 1000)
    }
}

/// Маса — потрібна калькулятору норми (макет 4a та онбординг).
public enum MassUnit: Int, Codable, CaseIterable, Sendable {
    case kilograms = 0
    case pounds = 1

    public var shortTitle: String {
        switch self {
        case .kilograms: return "кг"
        case .pounds: return "lb"
        }
    }
}

public enum Mass {
    public static let lbPerKg = 2.2046

    public static func display(_ kg: Double, in unit: MassUnit) -> Int {
        switch unit {
        case .kilograms: return Int(kg.rounded())
        case .pounds: return Int((kg * lbPerKg).rounded())
        }
    }
}
