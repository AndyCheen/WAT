import Foundation

/// Формат часу (WAT-56, SPEC-ONBOARDING §3.1): 24 години чи 12. Внутрішньо час — хвилини від 00:00,
/// формат — лише на межі UI, як і одиниці об'єму й ваги.
public enum TimeFormat: Int, Codable, CaseIterable, Sendable {
    case hours24 = 0
    case hours12 = 1

    /// «07:30» чи «7:30 дп». «дп / пп», а не «AM / PM» — так 12-годинний час пише сама iOS в українській локалі:
    /// латиниця в українському інтерфейсі — лише для майбутньої англійської локалізації (WAT-46).
    /// Відбій о 24:00 у 12-годинному — «12:00 дп», бо доба застосунку закінчується опівночі.
    public func clock(_ minutes: Int) -> String {
        switch self {
        case .hours24:
            return DaySchedule.clock(minutes)
        case .hours12:
            let hour = (minutes / 60) % 24
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            return String(format: "%d:%02d %@", hour12, minutes % 60, hour < 12 ? "дп" : "пп")
        }
    }

    /// Години блоку без хвилин — «08–12» / «8–11 дп», «11 дп–4 пп» (WAT-58): так у «Рівномірності» й віджеті
    /// «Ритм дня», де рядок вузький. Пів доби одна — «дп / пп» один раз у кінці; 24:00 — «12 дп», як у `clock`.
    public func hourRange(_ fromMinute: Int, _ toMinute: Int) -> String {
        switch self {
        case .hours24:
            return String(format: "%02d–%02d", (fromMinute / 60) % 24, (toMinute / 60) % 24)
        case .hours12:
            let (from, to) = (Self.hour12(fromMinute), Self.hour12(toMinute))
            return from.half == to.half
                ? "\(from.hour)–\(to.hour) \(to.half)"
                : "\(from.hour) \(from.half)–\(to.hour) \(to.half)"
        }
    }

    private static func hour12(_ minute: Int) -> (hour: Int, half: String) {
        let hour = (minute / 60) % 24
        return (hour % 12 == 0 ? 12 : hour % 12, hour < 12 ? "дп" : "пп")
    }
}

public extension DaySchedule {
    /// «06:30–22:00» / «6:30 дп–10:00 пп» — розклад у форматі людини (WAT-58).
    func label(_ format: TimeFormat) -> String {
        "\(format.clock(wakeMinutes))–\(format.clock(sleepMinutes))"
    }
}

public extension Mass {
    /// Кілограми з цілого значення в одиницях людини — зворотне до `display(_:in:)`. Не округлюється:
    /// інакше 154 фунти після збереження й читання ставали б 155.
    static func kilograms(_ value: Int, from unit: MassUnit) -> Double {
        switch unit {
        case .kilograms: return Double(value)
        case .pounds: return Double(value) / lbPerKg
        }
    }
}
