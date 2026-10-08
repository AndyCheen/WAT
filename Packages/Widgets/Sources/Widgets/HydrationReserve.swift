import Foundation

/// «Запас води» (SPEC-WIDGETS §5): скільки води ще вистачить до наступної склянки.
///
/// Запас не міряється, а виводиться з тієї ж моделі, що веде нагадування. Порція піднімає рівень
/// на свій об'єм (до ємності краплі), далі рівень рівно спадає й доходить до нуля **за 10 хв до
/// нагадування** — віджет спорожнів, і за 10 хв дзенькне. Нагадування відсувається, коли п'єш
/// більше, тож більша порція дає і вищий рівень, і довший спад.
///
/// Віджет зберігає лише прямий відрізок `(t₀, L₀) → (Z, 0)`: так рівень на будь-яку хвилину — проста
/// формула, а на екрані блокування його веде сама система (`ProgressView(timerInterval:)`).
public struct HydrationReserve: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Спадає до нагадування або до моменту, коли за темпом настав час пити.
        case flowing
        /// Норму закрито — повільно до відбою, без «Час пити».
        case goalMet
        /// Після відсічки нагадувань (далі вечірній підсумок, SPEC-NOTIFICATIONS §6.2) — до відбою.
        case evening
    }

    public var anchorAt: Date
    public var anchorMl: Double
    public var zeroAt: Date
    public var capacityMl: Int
    public var mode: Mode
    /// Коли час пити: нагадування з плану або момент, коли його поставила б крива темпу. Нуль — за 10 хв до нього.
    /// `nil` — пити «вчасно» вже не треба: закрита норма чи вечір.
    public var reminderAt: Date?
    /// `reminderAt` — справжнє заплановане сповіщення, а не розрахунок за темпом: лише тоді віджет каже «нагадаю о».
    public var reminderIsPlanned: Bool
    /// Порція, від якої рахується спад. Інша остання порція (нова чи undo) — новий розрахунок;
    /// та сама — рівень тягнеться без стрибків (`make`).
    public var lastIntakeId: UUID

    public init(anchorAt: Date, anchorMl: Double, zeroAt: Date, capacityMl: Int, mode: Mode,
                reminderAt: Date?, reminderIsPlanned: Bool = false, lastIntakeId: UUID) {
        self.anchorAt = anchorAt
        self.anchorMl = anchorMl
        self.zeroAt = zeroAt
        self.capacityMl = capacityMl
        self.mode = mode
        self.reminderAt = reminderAt
        self.reminderIsPlanned = reminderIsPlanned
        self.lastIntakeId = lastIntakeId
    }

    /// Рівень у мл о `date`: від `anchorMl` рівно до нуля в `zeroAt`.
    public func level(at date: Date) -> Double {
        Self.level(from: anchorMl, at: anchorAt, zeroAt: zeroAt, on: date)
    }

    /// Частка краплі — `level / C`.
    public func fraction(at date: Date) -> Double {
        capacityMl > 0 ? max(0, min(1, level(at: date) / Double(capacityMl))) : 0
    }

    /// Менше мілілітра — це вже нуль: інакше «Час пити» запізнювався б на хвилини дробового хвоста.
    public func isEmpty(at date: Date) -> Bool { level(at: date) < 1 }

    /// Початок інтервалу для `ProgressView(timerInterval: timerStart...zeroAt, countsDown: true)`.
    ///
    /// Системний прогрес-бар спадає від 1 до 0 на всьому інтервалі, а наш рівень у момент `t₀` — `L₀ / C`.
    /// Початок відсувається назад так, щоб у `t₀` частка інтервалу, що лишилась, дорівнювала `L₀ / C`:
    /// `start = Z − (Z − t₀) · C / L₀`. Далі обидва спадають лінійно до `Z` — збігаються в кожній точці.
    public var timerStart: Date {
        guard anchorMl > 0, capacityMl > 0 else { return zeroAt.addingTimeInterval(-1) }
        let span = zeroAt.timeIntervalSince(anchorAt) * Double(capacityMl) / anchorMl
        return zeroAt.addingTimeInterval(-max(1, span))
    }

    static func level(from ml: Double, at anchor: Date, zeroAt: Date, on date: Date) -> Double {
        guard date > anchor else { return ml }
        let span = zeroAt.timeIntervalSince(anchor)
        guard span > 0 else { return 0 }
        return ml * max(0, min(1, zeroAt.timeIntervalSince(date) / span))
    }
}

extension HydrationReserve {
    /// Нуль — за 10 хв до нагадування (рішення від 08.10.2026).
    public static let reminderLead: TimeInterval = 10 * 60
    /// Спад не коротший за 15 хв: чекпоінт може стояти одразу після порції, і крапля «згоріла» б на очах.
    public static let minimumSpan: TimeInterval = 15 * 60

    /// Ємність краплі — дві типові порції: звичайна склянка заповнює половину.
    public static func capacity(typicalPortionMl: Int) -> Int { 2 * max(1, typicalPortionMl) }

    /// Де закінчується спад після порції.
    public struct Zero: Equatable, Sendable {
        public var at: Date
        public var mode: Mode
        public var reminderAt: Date?

        public init(at: Date, mode: Mode, reminderAt: Date? = nil) {
            self.at = at
            self.mode = mode
            self.reminderAt = reminderAt
        }
    }

    /// Програвання порцій доби (SPEC-WIDGETS §5, п. 5).
    ///
    /// - Parameters:
    ///   - zero: де закінчується спад після порції — за кривою темпу, закритою нормою чи відсічкою. Для минулих
    ///     відрізків інших даних немає: план сповіщень знає лише майбутнє.
    ///   - plannedReminder: перше заплановане нагадування після останньої порції — з плану сповіщень, де вже
    ///     враховано тишу, чекпоінти й конфлікти. Замінює нуль останнього відрізка, якщо той «за темпом».
    ///   - previous: опублікований раніше запас. Та сама остання порція — рівень на «зараз» береться з нього,
    ///     і змінюється лише нахил: відкриття застосунку відсуває нагадування на 30 хв (§6.2, «Скидання»),
    ///     і крапля не мусить від цього підстрибнути. Порожня — лишається порожньою: нагадування вже могло прийти.
    /// - Returns: `nil`, якщо порцій ще немає — запас порожній, «Почни зі склянки».
    public static func make(
        portions: [WidgetSnapshot.Portion], capacityMl: Int, now: Date, plannedReminder: Date?,
        previous: HydrationReserve?, zero: (_ anchor: Date, _ drunkMl: Int) -> Zero
    ) -> HydrationReserve? {
        let sorted = portions.sorted { $0.at < $1.at }
        guard let last = sorted.last, capacityMl > 0 else { return nil }

        var level = 0.0
        var drunk = 0
        var segment: (anchor: Date, ml: Double, zero: Zero)?
        for portion in sorted {
            if let segment {
                level = Self.level(from: segment.ml, at: segment.anchor,
                                   zeroAt: max(segment.zero.at, segment.anchor.addingTimeInterval(minimumSpan)), on: portion.at)
            }
            level = min(Double(capacityMl), level + Double(portion.ml))
            drunk += portion.ml
            segment = (portion.at, level, zero(portion.at, drunk))
        }
        guard let segment else { return nil }
        var end = segment.zero
        var isPlanned = false
        if end.mode == .flowing, let plannedReminder, plannedReminder > segment.anchor {
            end = Zero(at: plannedReminder.addingTimeInterval(-reminderLead), mode: .flowing, reminderAt: plannedReminder)
            isPlanned = true
        }
        var result = HydrationReserve(
            anchorAt: segment.anchor, anchorMl: segment.ml,
            zeroAt: max(end.at, segment.anchor.addingTimeInterval(minimumSpan)),
            capacityMl: capacityMl, mode: end.mode, reminderAt: end.reminderAt, reminderIsPlanned: isPlanned,
            lastIntakeId: last.id
        )

        guard let previous, previous.lastIntakeId == last.id, previous.anchorAt <= now else { return result }
        let current = previous.level(at: now)
        if current < 1 || (previous.zeroAt == result.zeroAt && previous.mode == result.mode
                           && previous.reminderAt == result.reminderAt) {
            var kept = previous
            kept.capacityMl = capacityMl
            return kept
        }
        result.anchorAt = now
        result.anchorMl = current
        result.zeroAt = max(result.zeroAt, now)
        return result
    }
}
