import Foundation

/// Система об'єму (WAT-46). ТЗ §1: «обидві з перемиканням».
/// Внутрішньо все зберігається в мілілітрах — конвертація лише на межі UI й у текстах сповіщень.
///
/// США й Британія різняться лише множником: позначення в обох «oz», як на пляшках (рішення від 07.10.2026).
/// Унції — завжди цілі, без переходу в галони; метрична система показує «мл / л», як до WAT-46.
public enum VolumeUnit: Int, Codable, CaseIterable, Sendable {
    case milliliters = 0
    /// Колишнє `.fluidOunces` — тому raw 1.
    case usFluidOunces = 1
    case imperialFluidOunces = 2

    public var isMetric: Bool { self == .milliliters }

    public var mlPerUnit: Double {
        switch self {
        case .milliliters: return 1
        case .usFluidOunces: return 29.5735
        case .imperialFluidOunces: return 28.4131
        }
    }

    /// Підпис сегмента в налаштуваннях.
    public var shortTitle: String {
        switch self {
        case .milliliters: return "мл"
        case .usFluidOunces: return "oz США"
        case .imperialFluidOunces: return "oz UK"
        }
    }

    public var title: String {
        switch self {
        case .milliliters: return "Мілілітри й літри"
        case .usFluidOunces: return "Унції США"
        case .imperialFluidOunces: return "Британські унції"
        }
    }

    public static let ounceSymbol = "oz"

    /// Значення в одиницях системи: мілілітри як є, унції — округлені до цілих.
    public func units(_ ml: Int) -> Int {
        isMetric ? ml : Int((Double(ml) / mlPerUnit).rounded())
    }

    public func milliliters(units: Int) -> Int {
        isMetric ? units : Int((Double(units) * mlPerUnit).rounded())
    }

    /// Скільки бракує — вгору до цілої унції, щоб людина не недобрала.
    public func unitsRoundedUp(_ ml: Int) -> Int {
        isMetric ? ml : Int((Double(max(0, ml)) / mlPerUnit).rounded(.up))
    }

    /// Підпис об'єму: в унціях — «8 oz», у метричній — те, що скаже місце показу. Кожне місце має свій
    /// метричний формат («1.25 л» на кільці, «1,05 л» у сповіщенні), і на них стоять тести й e2e.
    public func format(_ ml: Int, metric: (Int) -> String) -> String {
        isMetric ? metric(ml) : "\(units(ml)) \(Self.ounceSymbol)"
    }

    /// Наступне значення на сітці в одиницях системи. Крок — від *показаного* значення: «8 oz» —
    /// це 237 мл, і крок униз від 237 мл не має знову дати «8 oz».
    public func stepped(_ ml: Int, up: Bool, grid: VolumeGrid) -> Int {
        milliliters(units: grid.stepped(units(ml), up: up))
    }

    /// Найближчий вузол сітки — для перемикання системи.
    public func snapped(_ ml: Int, grid: VolumeGrid) -> Int {
        milliliters(units: grid.snapped(units(ml)))
    }
}

/// Сітка степера в одиницях системи: дрібний крок до `coarseFrom`, далі — грубий.
public struct VolumeGrid: Equatable, Sendable {
    public let fine: Int
    public let coarse: Int
    public let coarseFrom: Int

    public init(fine: Int, coarse: Int, coarseFrom: Int) {
        self.fine = fine
        self.coarse = coarse
        self.coarseFrom = coarseFrom
    }

    public init(step: Int) {
        self.init(fine: step, coarse: step, coarseFrom: .max)
    }

    /// Значення поза сіткою стає на найближчий вузол у бік кроку, а не тягне зсув далі.
    public func stepped(_ value: Int, up: Bool) -> Int {
        if up {
            let step = value < coarseFrom ? fine : coarse
            return (value / step + 1) * step
        }
        let step = value <= coarseFrom ? fine : coarse
        return ((value - 1) / step) * step
    }

    public func snapped(_ value: Int) -> Int {
        let step = value < coarseFrom ? fine : coarse
        return max(step, Int((Double(value) / Double(step)).rounded()) * step)
    }
}

public enum Volume {
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
