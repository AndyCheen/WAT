import Foundation

/// Частини доби — використовуються в графіку рівномірності, «типовій добі»
/// та в правилах завдань («випий 500 мл до 12:00»).
///
/// Межі за замовчуванням зафіксовані в PLAN.md §12.7 і можуть бути змінені в одному місці.
public enum DayPart: Int, CaseIterable, Codable, Sendable, Identifiable {
    case morning = 0   // Ранок     05:00–09:00
    case noon          // Полудень  09:00–12:00
    case afternoon     // День      12:00–17:00
    case evening       // Вечір     17:00–22:00
    case night         // Ніч       22:00–05:00

    public var id: Int { rawValue }

    /// Стабільний латинський ключ — для ідентифікаторів сповіщень і `refId` XP.
    public var key: String {
        switch self {
        case .morning: return "morning"
        case .noon: return "noon"
        case .afternoon: return "afternoon"
        case .evening: return "evening"
        case .night: return "night"
        }
    }

    public var title: String {
        switch self {
        case .morning: return "Ранок"
        case .noon: return "Полудень"
        case .afternoon: return "День"
        case .evening: return "Вечір"
        case .night: return "Ніч"
        }
    }

    /// Напівінтервал [from, to) у годинах; `night` перетинає північ.
    public var hours: (from: Int, to: Int) {
        switch self {
        case .morning: return (5, 9)
        case .noon: return (9, 12)
        case .afternoon: return (12, 17)
        case .evening: return (17, 22)
        case .night: return (22, 5)
        }
    }

    public static func from(hour: Int) -> DayPart {
        switch hour {
        case 5..<9: return .morning
        case 9..<12: return .noon
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default: return .night
        }
    }

    /// Вага частини доби в кривій темпу (сума = 1.0) — за повних активних годин.
    /// Ціль конкретного дня — не ця частка, а `PaceCurve.partTargetsMl()`: частина, обрізана
    /// підйомом чи відбоєм, бере пропорційно менше, а поза активними годинами — нуль (WAT-39).
    /// Спад перед сном — не тут, а в `PaceCurve.taperMinutes`: ці ваги прив'язані до годинника,
    /// а спад — до відбою людини (WAT-43).
    public var idealShare: Double {
        switch self {
        case .morning: return 0.20
        case .noon: return 0.20
        case .afternoon: return 0.30
        case .evening: return 0.22
        case .night: return 0.08
        }
    }
}
