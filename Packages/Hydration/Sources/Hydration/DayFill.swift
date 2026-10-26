import Foundation
import Core

/// Об'єм дня порціями — «заповнити день» у режимі розробника (WAT-68). Чиста функція: що й коли додати, вирішує
/// тут, а додає `HydrationService.addIntake` — тим самим шляхом, що й порція з головного.
public enum DayFill {
    public struct Portion: Equatable, Sendable {
        public let minute: Int
        public let ml: Int
    }

    /// Звична порція, від якої рахується кількість порцій.
    static let typicalMl = 300
    /// Більше 12 порцій за день — уже не «звичайний день», і заповнення 30 днів тягнулося б помітно довше.
    static let maxPortions = 12
    /// Порції не ближче за це одна до одної: кілька в одну хвилину відкрили б пасхалки «серією за хвилину».
    static let minGapMinutes = 20

    /// Рівно по активних годинах, кратно 50 мл, без порції за 30 хв до відбою — так виглядає звичайний день людини,
    /// а не демо-хвилі. `untilMinute` — сьогодні: порцій із майбутнього не буває.
    public static func portions(totalMl: Int, schedule: DaySchedule, untilMinute: Int? = nil) -> [Portion] {
        let units = (max(0, totalMl) + 25) / 50
        guard units > 0 else { return [] }
        let count = min(max(1, Int((Double(totalMl) / Double(typicalMl)).rounded(.up))), maxPortions, units)

        var end = max(schedule.wakeMinutes + 1, schedule.sleepMinutes - 30)
        if let untilMinute { end = min(end, untilMinute) }
        let start = max(0, min(schedule.wakeMinutes, end - (count - 1) * minGapMinutes))

        let base = units / count, extra = units % count
        return (0..<count).map { index in
            let minute = count == 1 ? (start + end) / 2 : start + (end - start) * index / (count - 1)
            return Portion(minute: minute, ml: (base + (index < extra ? 1 : 0)) * 50)
        }
    }
}
