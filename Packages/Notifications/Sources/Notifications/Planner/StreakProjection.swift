import Foundation

/// Серія на дні плану з припущенням «користувач більше нічого не робить» (§16.2): що відомо
/// про сьогодні, учора й позавчора — береться як є, майбутні дні не зараховані.
///
/// `rel` — зсув від сьогодні: −2 позавчора, 0 сьогодні, 2 післязавтра.
struct StreakProjection {
    let input: StreakInput
    let minStreak: Int

    func counted(_ rel: Int) -> Bool {
        switch rel {
        case 0: return input.countedToday
        case -1: return input.countedYesterday
        case -2: return input.countedDayBefore
        default: return false
        }
    }

    func length(endingAt rel: Int) -> Int {
        switch rel {
        case 0: return input.lengthEndingToday
        case -1: return input.lengthEndingYesterday
        case -2: return input.lengthEndingDayBefore
        default: return 0
        }
    }

    /// Ранковий порятунок: учора пропущено, а позавчора закінчилась серія ≥ 3 —
    /// заморозка ще рятує її (`freezeTarget == .yesterday`, §12.1). Повертає число серії.
    func morningRescue(on rel: Int) -> Int? {
        guard !counted(rel - 1), counted(rel - 2), length(endingAt: rel - 2) >= minStreak else { return nil }
        return length(endingAt: rel - 2)
    }

    /// Вечірній порятунок: учора зараховано, сьогодні ні (`freezeTarget == .today`).
    func eveningRescue(on rel: Int) -> Int? {
        streakAtStake(on: rel)
    }

    /// Серія ≥ 3 тримається на нормі цього дня — вставка «…серія тримається на сьогоднішній нормі».
    func streakAtStake(on rel: Int) -> Int? {
        guard counted(rel - 1), !counted(rel), length(endingAt: rel - 1) >= minStreak else { return nil }
        return length(endingAt: rel - 1)
    }

    /// Серія, яку продовжить сьогоднішня норма (будь-якої довжини) — для «можна закрити + серія».
    func continuingStreak(on rel: Int) -> Int? {
        guard counted(rel - 1), length(endingAt: rel - 1) >= 1 else { return nil }
        return length(endingAt: rel - 1)
    }
}
