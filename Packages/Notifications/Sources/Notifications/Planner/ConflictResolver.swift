import Foundation

/// «Один момент — одне сповіщення» (§3.1, п. 3; §13.3).
///
/// Кандидати приймаються від сильнішого до слабшого. Той, хто ближче ніж за 30 хв до вже
/// прийнятого чи вже показаного:
/// - основне нагадування зсувається на +30 хв від сильнішого (якщо ще встигає до відсічки);
/// - повторне скасовується;
/// - фіксовані типи (ранок, вечір, повернення) поступаються сильнішому, а показаному —
///   зсуваються; порятунок не скасовується ніколи.
struct ConflictResolver {
    let spacing: TimeInterval
    let frame: DayFrame

    func resolve(_ candidates: [Candidate], shown: [Date]) -> [Candidate] {
        var accepted: [Candidate] = []
        let ordered = candidates.sorted {
            ($0.item.priority, $0.item.fireAt) < ($1.item.priority, $1.item.fireAt)
        }

        for candidate in ordered {
            var current = candidate
            var placed = false
            // Кожен зсув іде вперед щонайменше на 30 хв — цикл скінченний.
            for _ in 0..<12 {
                let t = current.item.fireAt
                let strongerConflict = accepted.first { abs($0.item.fireAt.timeIntervalSince(t)) < spacing }
                let shownConflict = shown.first { abs($0.timeIntervalSince(t)) < spacing }
                guard let blocker = strongerConflict?.item.fireAt ?? shownConflict else {
                    placed = true
                    break
                }
                let canMove: Bool
                switch current.item.priority {
                case .reminderFollowUp: canMove = false
                case .reminderPrimary, .rescue: canMove = true
                default: canMove = strongerConflict == nil
                }
                let limit = current.item.type == .reminder ? frame.cutoff : frame.sleep
                guard canMove, let moved = frame.place(blocker.addingTimeInterval(spacing), limit: limit) else { break }
                current.item.fireAt = moved
            }
            if placed { accepted.append(current) }
        }
        return accepted.sorted { $0.item.fireAt < $1.item.fireAt }
    }
}

/// ≤ 8 активних на день (§13.1). Коли ліміт вичерпано, проходить лише порятунок серії.
/// Скорочення — з найслабших і найпізніших: спершу повторні, потім основні нагадування,
/// потім ранок і повернення, останнім — вечірній підсумок.
enum DailyCap {
    static func apply(_ candidates: [Candidate], shownCount: Int, cap: Int) -> [Candidate] {
        var kept = candidates
        let order: [NotificationPriority] = [.reminderFollowUp, .reminderPrimary, .checkpoint, .challenge, .morning, .evening]
        for priority in order {
            while shownCount + kept.count > cap,
                  let index = kept.lastIndex(where: { $0.item.priority == priority }) {
                kept.remove(at: index)
            }
        }
        return kept
    }
}
