import Foundation
import Core
import Persistence

/// Складає заголовок і текст кожного сповіщення плану (SPEC-NOTIFICATIONS §14).
///
/// - Варіант вибирається детерміновано — стабільний хеш ідентифікатора, щоб тести не «плавали»;
///   два останні використані варіанти цього типу підряд не повторюються (журнал + раніші
///   сповіщення того самого плану).
/// - Контекст (серія на кону, буст, завдання, «Знову в ритмі») — одна вставка на сповіщення
///   за пріоритетом §12.2. Вставка заміняє останнє речення варіанта, а не дописується:
///   інакше текст виходить за 100 символів (§14.3).
struct TextComposer {
    let builder: PlanBuilder

    private var context: NotificationContext { builder.context }
    private static let bodyLimit = 100

    func compose(_ candidates: [Candidate]) -> [PlannedNotification] {
        var recent: [NotificationType: [Int]] = [:]
        var result: [PlannedNotification] = []
        for candidate in candidates {
            var item = candidate.item
            if item.type == .reminder {
                item.id = "wt.reminder.\(item.dayKey.rawValue).\(clockSlot(item.fireAt))"
            }

            let used = (recent[item.type] ?? []) + builder.journal.recentVariants(of: item.type, before: builder.now)
            let variant = pick(variants(for: candidate), seed: item.id, avoiding: Array(used.prefix(2)))
            item.variant = variant.id
            item.title = fill(variant.title, candidate)
            item.body = withInsert(fill(variant.body, candidate), insert(for: candidate, variant: variant))

            recent[item.type, default: []].insert(variant.id, at: 0)
            result.append(item)
        }
        return result
    }

    // MARK: - Варіанти

    private func variants(for candidate: Candidate) -> [CopyVariant] {
        let all: [CopyVariant]
        switch candidate.copy {
        case .reminder(let followUp, _, _): all = followUp ? NotificationCopy.reminderFollowUp : NotificationCopy.reminderPrimary
        case .morning: all = NotificationCopy.morning
        case .eveningClosable(_, let streak):
            all = streak == nil ? NotificationCopy.eveningClosable : NotificationCopy.eveningStreak
        case .eveningSoothing: all = NotificationCopy.eveningSoothing
        case .rescueEvening: all = NotificationCopy.rescueEvening
        case .rescueMorning: all = NotificationCopy.rescueMorning
        case .checkpoint: all = NotificationCopy.checkpoint
        case .reportDay: all = [NotificationCopy.reportDay]
        case .reportWeek: all = [NotificationCopy.reportWeek]
        case .reportMonth: all = [NotificationCopy.reportMonth]
        case .reportWeekMonth: all = [NotificationCopy.reportWeekMonth]
        case .comeback(let number, let gift):
            if number == 1 { all = NotificationCopy.comebackFirst }
            else { all = [gift ? NotificationCopy.comebackLastWithGift : NotificationCopy.comebackLast] }
        }
        return all.filter { variant in variant.requires.allSatisfy { satisfied($0, candidate) } }
    }

    private func satisfied(_ requirement: CopyVariant.Requirement, _ candidate: Candidate) -> Bool {
        switch requirement {
        case .since:
            if case .reminder(_, _, let last) = candidate.copy { return last != nil }
            return false
        case .morningQuest:
            return candidate.rel == 0 && context.quests.morningQuestActive
        case .singleGlass:
            if case .eveningClosable(let left, _) = candidate.copy { return left <= builder.preferences.glassMl }
            return false
        }
    }

    private func pick(_ variants: [CopyVariant], seed: String, avoiding used: [Int]) -> CopyVariant {
        var pool = variants.filter { !used.contains($0.id) }
        if pool.isEmpty { pool = variants.filter { $0.id != used.first } }
        if pool.isEmpty { pool = variants }
        let index = Int(StableHash.fnv1a(seed) % UInt64(pool.count))
        return pool[index]
    }

    // MARK: - Плейсхолдери

    private func fill(_ template: String, _ candidate: Candidate) -> String {
        var text = template
        let unit = builder.preferences.volumeUnit
        text = text.replacingOccurrences(of: "{glass}", with: NotificationFormat.volume(builder.preferences.glassMl, unit))
        switch candidate.copy {
        case .reminder(_, let left, let last):
            text = text.replacingOccurrences(of: "{left}", with: NotificationFormat.left(left, unit))
            if let last {
                let minutes = Int(candidate.item.fireAt.timeIntervalSince(last) / 60)
                text = text.replacingOccurrences(of: "{since}", with: NotificationFormat.duration(minutes: minutes))
            }
        case .eveningClosable(let left, let streak):
            text = text.replacingOccurrences(of: "{left}", with: NotificationFormat.left(left, unit))
            if let streak { text = text.replacingOccurrences(of: "{streak}", with: NotificationFormat.days(streak)) }
        case .eveningSoothing(let total):
            text = text.replacingOccurrences(of: "{total}", with: NotificationFormat.volume(total, unit))
        case .rescueEvening(let streak), .rescueMorning(let streak):
            text = text.replacingOccurrences(of: "{streak}", with: NotificationFormat.days(streak))
        case .checkpoint(let left, let deadline, let part, let xp):
            text = text.replacingOccurrences(of: "{left}", with: NotificationFormat.left(left, unit))
            text = text.replacingOccurrences(of: "{deadline}", with: clockLabel(deadline))
            text = text.replacingOccurrences(of: "{part}", with: part.title.lowercased())
            text = text.replacingOccurrences(of: "{xp}", with: "\(xp)")
        case .reportDay(let digest, let streak):
            text = text.replacingOccurrences(of: "{report}", with: ReportText.day(digest, streak: streak, unit: unit))
        case .reportWeek(let digest):
            text = text.replacingOccurrences(of: "{goalDays}", with: "\(digest.goalDays)")
                .replacingOccurrences(of: "{dayCount}", with: "\(digest.dayCount)")
                .replacingOccurrences(of: "{report}", with: ReportText.week(digest, unit: unit))
        case .reportMonth(let digest):
            text = text.replacingOccurrences(of: "{month}", with: ReportText.monthName(digest.period))
                .replacingOccurrences(of: "{goalDaysPlural}", with: Plural.days(digest.goalDays))
                .replacingOccurrences(of: "{report}", with: ReportText.month(digest, unit: unit))
        case .reportWeekMonth(let week, let month):
            text = text.replacingOccurrences(of: "{report}", with: ReportText.weekMonth(week: week, month: month))
        case .morning, .comeback:
            break
        }
        return text
    }

    // MARK: - Вставки контексту (§12.2)

    private func insert(for candidate: Candidate, variant: CopyVariant) -> String? {
        let projection = builder.projection
        switch candidate.copy {
        case .reminder:
            if let streak = projection.streakAtStake(on: candidate.rel) {
                return NotificationCopy.streakInsert(streak)
            }
            if let expires = context.boostExpiresAt, expires > candidate.item.fireAt {
                let minutes = Int(expires.timeIntervalSince(candidate.item.fireAt) / 60)
                return NotificationCopy.boostInsert(remaining: NotificationFormat.duration(minutes: minutes))
            }
            if candidate.rel == 0, let title = context.quests.oneEntryLeftTitle {
                return NotificationCopy.questInsert(title: title)
            }
            return bounceBackInsert(candidate)
        case .eveningClosable:
            if candidate.rel == 0, let weekly = context.quests.weeklyClosesToday {
                return NotificationCopy.weeklyInsert(xp: weekly.xp)
            }
            return bounceBackInsert(candidate)
        case .morning:
            return bounceBackInsert(candidate)
        default:
            return nil
        }
    }

    /// «Знову в ритмі» доступне в цей день — якщо немає ранкового порятунку: заморозка
    /// збереже саму серію, тож вона важливіша (§12.5 Б, «Анонс»).
    private func bounceBackInsert(_ candidate: Candidate) -> String? {
        let projection = builder.projection
        let rel = candidate.rel
        guard !projection.counted(rel), !projection.counted(rel - 1), projection.counted(rel - 2),
              projection.length(endingAt: rel - 2) >= context.bounceBackMinStreak else { return nil }
        if builder.preferences.rescueEnabled, context.readyFreezes > 0 { return nil }
        if let last = context.lastBounceBackDay,
           builder.service.daysBetween(last, candidate.item.dayKey) < context.bounceBackCooldownDays {
            return nil
        }
        return NotificationCopy.bounceBackInsert(xp: context.bounceBackXp)
    }

    /// Вставка заміняє останнє речення; якщо так виходить задовго — заміняє весь текст;
    /// однореченнєвий текст доповнюється (рішення від 04.10.2026).
    private func withInsert(_ body: String, _ insert: String?) -> String {
        guard let insert else { return body }
        let sentences = body.components(separatedBy: ". ")
        let options = sentences.count > 1
            ? [(sentences.dropLast() + [insert]).joined(separator: ". "), insert]
            : [body + ". " + insert, insert]
        return options.first { $0.count <= Self.bodyLimit } ?? body
    }

    /// «12:00» — дедлайн чекпоінта.
    private func clockLabel(_ date: Date) -> String {
        let parts = builder.service.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func clockSlot(_ date: Date) -> String {
        let parts = builder.service.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
