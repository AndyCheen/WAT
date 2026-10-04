import Foundation

/// Крива темпу `E(t)` — скільки мілілітрів «за темпом» варто випити від підйому до хвилини `t`
/// (SPEC-NOTIFICATIONS §4).
///
/// Ваги — ті самі `DayPart.idealShare`, що дають ризки «ціль» у «Рівномірності» на 4a: тоді
/// «відстав від темпу» в сповіщенні означає те саме, що на графіку. Частина доби, обрізана
/// активними годинами `[W, S]`, отримує частку своєї ваги пропорційно годинам, що лишились;
/// ваги нормуються до 1, усередині частини крива лінійна.
///
/// Для норми 2000 мл і 08:00–22:00: ранок 08–09 бере ¼ своїх 20 %, ніч випадає, і після
/// нормування на 0,77 виходить E(09:00) = 130, E(12:00) = 649, E(17:00) = 1429 — таблиця §4.
///
/// Час — хвилини від локальної півночі, а не `Date`: крива не знає ні поясу, ні дати, і тому
/// лишається чистою функцією для Notifications, Insights і Gamification.
public struct PaceCurve: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public let part: DayPart
        public let fromMinute: Int
        public let toMinute: Int
        /// Скільки мілілітрів норми припадає на цей відрізок.
        public let ml: Double
    }

    public let goalMl: Int
    public let wakeMinutes: Int
    public let sleepMinutes: Int
    /// Відрізки частин доби в межах `[W, S]`, за зростанням часу.
    public let segments: [Segment]

    public init(goalMl: Int, wakeMinutes: Int, sleepMinutes: Int) {
        let wake = max(0, min(wakeMinutes, 24 * 60))
        let sleep = max(wake, min(sleepMinutes, 24 * 60))
        self.goalMl = goalMl
        self.wakeMinutes = wake
        self.sleepMinutes = sleep

        var raw: [(part: DayPart, from: Int, to: Int, weight: Double)] = []
        for part in DayPart.allCases {
            let pieces = Self.pieces(of: part)
            let fullLength = Double(pieces.reduce(0) { $0 + ($1.to - $1.from) })
            for piece in pieces {
                let from = max(piece.from, wake)
                let to = min(piece.to, sleep)
                guard to > from else { continue }
                raw.append((part, from, to, part.idealShare * Double(to - from) / fullLength))
            }
        }
        let total = raw.reduce(0) { $0 + $1.weight }
        self.segments = raw
            .sorted { $0.from < $1.from }
            .map { Segment(part: $0.part, fromMinute: $0.from, toMinute: $0.to,
                           ml: total > 0 ? Double(goalMl) * $0.weight / total : 0) }
    }

    /// `E(t)`: 0 до підйому, уся норма після відбою, лінійно всередині частини доби.
    public func expected(atMinute minute: Double) -> Double {
        if minute <= Double(wakeMinutes) { return 0 }
        if minute >= Double(sleepMinutes) { return Double(goalMl) }
        var sum = 0.0
        for segment in segments {
            let from = Double(segment.fromMinute), to = Double(segment.toMinute)
            if minute >= to {
                sum += segment.ml
            } else {
                if minute > from { sum += segment.ml * (minute - from) / (to - from) }
                break
            }
        }
        return sum
    }

    /// Найраніша хвилина в `[W, S]`, коли крива досягає `ml`; `nil`, якщо не досягає до відбою.
    ///
    /// `tolerance` — запас на похибку `Double`: межа частини доби, рівна цілі в раціональних
    /// числах (E(14:15) = 1000 рівно), інакше могла б зсунути нагадування на хвилину.
    public func minute(reaching ml: Double, tolerance: Double = 1e-6) -> Double? {
        if ml <= tolerance { return Double(wakeMinutes) }
        if ml > Double(goalMl) + tolerance { return nil }
        var sum = 0.0
        for segment in segments {
            let from = Double(segment.fromMinute), to = Double(segment.toMinute)
            if sum + segment.ml >= ml - tolerance {
                guard segment.ml > 0 else { return from }
                let fraction = max(0, min(1, (ml - sum) / segment.ml))
                return from + (to - from) * fraction
            }
            sum += segment.ml
        }
        return Double(sleepMinutes)
    }

    /// Ціль на відрізок `[from, to)` — для чекпоінтів частин доби (етап B, §9).
    public func target(fromMinute: Double, toMinute: Double) -> Double {
        expected(atMinute: toMinute) - expected(atMinute: fromMinute)
    }

    /// Ніч 22:00–05:00 перетинає північ — у хвилинах доби це два шматки.
    private static func pieces(of part: DayPart) -> [(from: Int, to: Int)] {
        let (from, to) = part.hours
        if from < to { return [(from * 60, to * 60)] }
        return [(0, to * 60), (from * 60, 24 * 60)]
    }
}
