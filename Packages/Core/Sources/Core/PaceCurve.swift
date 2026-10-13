import Foundation

/// Крива темпу `E(t)` — скільки мілілітрів «за темпом» варто випити від підйому до хвилини `t`
/// (SPEC-NOTIFICATIONS §4).
///
/// Ваги — `DayPart.idealShare`. Ризки «ціль» на графіках 4a беруться з цієї ж кривої
/// (`partTargetsMl`), тож «відстав від темпу» в сповіщенні означає те саме, що на графіку. Частина доби, обрізана
/// активними годинами `[W, S]`, отримує частку своєї ваги пропорційно годинам, що лишились;
/// ваги нормуються до 1, усередині частини крива лінійна.
///
/// Останні `taperMinutes` до відбою темп удвічі нижчий (рішення від 05.10.2026, WAT-43, §29):
/// вода в останні 2 год перед сном — це нічні пробудження, а лінійний вечір чекав там 229 мл.
/// Вікно рахується від відбою людини, а не від годинника, тому ваги частин доби не чіпаються.
///
/// Для норми 2000 мл і 08:00–22:00: ранок 08–09 бере ¼ своїх 20 %, ніч випадає, вечір 20–22 —
/// половину своєї ваги, і після нормування на 0,726 виходить E(09:00) = 138, E(12:00) = 689,
/// E(17:00) = 1515 — таблиця §4.
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
    ///
    /// Спад перед сном їх не ділить: вечір 20–22 окремим відрізком став би окремою ціллю
    /// в `goalBlocks()` і дав би зайвий чекпоінт «до 20:00».
    public let segments: [Segment]
    /// Лінійні шматки кривої: відрізки, розрізані на початку спаду. По них рахується `E(t)`.
    private let pieces: [Piece]

    private struct Piece: Sendable, Equatable {
        let fromMinute: Int
        let toMinute: Int
        let ml: Double
    }

    /// Скільки хвилин перед відбоєм темп знижений — як `eveningLead` вечірнього підсумку (§8) і
    /// «за 2 год до сну» в EAU та CUA (§29).
    public static let taperMinutes = 120
    /// У скільки разів темп нижчий у вікні спаду. Не нуль: вода ввечері потрібна, а недопити
    /// теж шкодить сну (§29).
    public static let taperFactor = 0.5

    public init(goalMl: Int, wakeMinutes: Int, sleepMinutes: Int) {
        let wake = max(0, min(wakeMinutes, 24 * 60))
        let sleep = max(wake, min(sleepMinutes, 24 * 60))
        self.goalMl = goalMl
        self.wakeMinutes = wake
        self.sleepMinutes = sleep
        let taperStart = max(wake, sleep - Self.taperMinutes)

        var raw: [(part: DayPart, from: Int, to: Int, pieces: [(from: Int, to: Int, weight: Double)])] = []
        for part in DayPart.allCases {
            let partPieces = Self.pieces(of: part)
            let fullLength = Double(partPieces.reduce(0) { $0 + ($1.to - $1.from) })
            let perMinute = part.idealShare / fullLength
            for piece in partPieces {
                let from = max(piece.from, wake)
                let to = min(piece.to, sleep)
                guard to > from else { continue }
                var sub: [(from: Int, to: Int, weight: Double)] = []
                if from < taperStart {
                    let end = min(to, taperStart)
                    sub.append((from, end, perMinute * Double(end - from)))
                }
                if to > taperStart {
                    let start = max(from, taperStart)
                    sub.append((start, to, perMinute * Self.taperFactor * Double(to - start)))
                }
                raw.append((part, from, to, sub))
            }
        }
        raw.sort { $0.from < $1.from }
        let total = raw.reduce(0) { sum, segment in segment.pieces.reduce(sum) { $0 + $1.weight } }
        let scale = total > 0 ? Double(goalMl) / total : 0
        self.segments = raw.map { segment in
            Segment(part: segment.part, fromMinute: segment.from, toMinute: segment.to,
                    ml: segment.pieces.reduce(0) { $0 + $1.weight } * scale)
        }
        self.pieces = raw.flatMap { segment in
            segment.pieces.map { Piece(fromMinute: $0.from, toMinute: $0.to, ml: $0.weight * scale) }
        }
    }

    /// `E(t)`: 0 до підйому, уся норма після відбою, лінійно всередині частини доби (і окремо
    /// лінійно у вікні спаду).
    public func expected(atMinute minute: Double) -> Double {
        if minute <= Double(wakeMinutes) { return 0 }
        if minute >= Double(sleepMinutes) { return Double(goalMl) }
        var sum = 0.0
        for piece in pieces {
            let from = Double(piece.fromMinute), to = Double(piece.toMinute)
            if minute >= to {
                sum += piece.ml
            } else {
                if minute > from { sum += piece.ml * (minute - from) / (to - from) }
                break
            }
        }
        return sum
    }

    /// Найраніша хвилина в `[W, S]`, коли крива досягає `ml`; `nil`, якщо не досягає до відбою.
    ///
    /// `tolerance` — запас на похибку `Double`: межа частини доби, рівна цілі в раціональних
    /// числах (E(13:53) = 1000 рівно), інакше могла б зсунути нагадування на хвилину.
    public func minute(reaching ml: Double, tolerance: Double = 1e-6) -> Double? {
        if ml <= tolerance { return Double(wakeMinutes) }
        if ml > Double(goalMl) + tolerance { return nil }
        var sum = 0.0
        for piece in pieces {
            let from = Double(piece.fromMinute), to = Double(piece.toMinute)
            if sum + piece.ml >= ml - tolerance {
                guard piece.ml > 0 else { return from }
                let fraction = max(0, min(1, (ml - sum) / piece.ml))
                return from + (to - from) * fraction
            }
            sum += piece.ml
        }
        return Double(sleepMinutes)
    }

    /// Ціль на відрізок `[from, to)` — для чекпоінтів частин доби (етап B, §9).
    public func target(fromMinute: Double, toMinute: Double) -> Double {
        expected(atMinute: toMinute) - expected(atMinute: fromMinute)
    }

    /// Ціль на відрізок у цілих мілілітрах — різниця округлених `E`, а не округлена різниця:
    /// так цілі сусідніх відрізків складаються точно в норму (689 + 826 + 485 = 2000), і «ранок
    /// 138 + полудень 551» на графіку дорівнює 689 у звіті (WAT-39).
    public func roundedTarget(fromMinute: Int, toMinute: Int) -> Int {
        Int(expected(atMinute: Double(toMinute)).rounded()) - Int(expected(atMinute: Double(fromMinute)).rounded())
    }

    /// Цілі п'яти частин доби в мл, індекс — `DayPart.rawValue`: шматок кривої в межах активних
    /// годин. Частина поза ними (зазвичай ніч) отримує 0 — вночі пити не очікуємо (§13.6).
    /// Це ризки «ціль» на графіках 4a — та сама модель, що в чекпоінта, XP і звіту.
    public func partTargetsMl() -> [Int] {
        var result = Array(repeating: 0, count: DayPart.allCases.count)
        for segment in segments {
            result[segment.part.rawValue] += roundedTarget(fromMinute: segment.fromMinute, toMinute: segment.toMinute)
        }
        return result
    }

    /// Частки норми по частинах доби (сума = 1, якщо є активні години) — для балу рівномірності
    /// й «Типової доби». Без округлення: бал не має стрибати від мілілітра.
    public func partShares() -> [Double] {
        var result = Array(repeating: 0.0, count: DayPart.allCases.count)
        guard goalMl > 0 else { return result }
        for segment in segments {
            result[segment.part.rawValue] += segment.ml / Double(goalMl)
        }
        return result
    }

    /// Ніч 22:00–05:00 перетинає північ — у хвилинах доби це два шматки.
    private static func pieces(of part: DayPart) -> [(from: Int, to: Int)] {
        let (from, to) = part.hours
        if from < to { return [(from * 60, to * 60)] }
        return [(0, to * 60), (from * 60, 24 * 60)]
    }
}

extension PaceCurve {
    /// Коли за темпом настав час наступної порції — перше нагадування ланцюга (SPEC-NOTIFICATIONS §6.2):
    /// `R = max(A, E(L))`, перший момент `t ∈ [L + minGap, L + maxGap]`, де `E(t) − R ≥ k·P`, інакше `L + maxGap`.
    ///
    /// У `Core`, а не в планувальнику: та сама формула веде «Запас води» у віджеті (WAT-30, SPEC-WIDGETS §5),
    /// і віджет мусить спорожніти саме тоді, коли нагадування вирішить, що час пити. Без округлення до
    /// хвилини й без тиші — це вже справа планувальника.
    public func nextDueMinute(anchorMinute: Double, drunkMl: Int, portionMl: Int,
                              k: Double, minGapMinutes: Int, maxGapMinutes: Int) -> Double {
        // `max(A, E(L))`: старий дефіцит — справа вечірнього підсумку, нагадування стежить лише за
        // поточним ритмом. З просто `A` нарада давала 8 нагадувань замість 4 (§6.2).
        let base = max(Double(drunkMl), expected(atMinute: anchorMinute))
        let low = anchorMinute + Double(minGapMinutes)
        let high = anchorMinute + Double(maxGapMinutes)
        guard let reach = minute(reaching: base + k * Double(portionMl)), reach <= high else { return high }
        return max(low, reach)
    }
}
