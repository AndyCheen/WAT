import Foundation
import Core
import Persistence

/// Тестове сповіщення будь-якої ситуації — режим розробника (WAT-68). Та сама категорія дій, той самий перехід за
/// тапом і текст від `TextComposer`, що й у плані, — лише приходить за кілька секунд, а не тоді, коли його поставив би
/// планувальник. Числа в тексті — з поточного дня, а де їх немає (серія 0, звіту ще нема) — правдоподібні.
public enum NotificationSample: String, CaseIterable, Sendable {
    case reminder, reminderFollowUp, checkpoint, challenge, morning
    case eveningClosable, eveningStreak, eveningClose, eveningSoothing
    case rescueMorning, rescueEvening, comebackFirst, comebackLast
    case reportDay, reportWeek, reportMonth

    public var type: NotificationType {
        switch self {
        case .reminder, .reminderFollowUp: return .reminder
        case .checkpoint: return .checkpoint
        case .challenge: return .challenge
        case .morning: return .morning
        case .eveningClosable, .eveningStreak, .eveningClose, .eveningSoothing: return .evening
        case .rescueMorning, .rescueEvening: return .rescue
        case .comebackFirst, .comebackLast: return .comeback
        case .reportDay, .reportWeek, .reportMonth: return .report
        }
    }
}

extension NotificationPlanner {
    /// Сповіщення-зразок на мить `fireAt` — без правил частоти, тихих годин і ліміту на день.
    public static func sample(
        _ sample: NotificationSample, fireAt: Date, context: NotificationContext,
        preferences: NotificationPreferences, journal: NotificationJournal = .empty, rules: NotificationRules = .default
    ) -> PlannedNotification {
        let builder = PlanBuilder(context: context, preferences: preferences, journal: journal, rules: rules)
        let candidate = builder.sampleCandidate(sample, at: fireAt)
        var item = TextComposer(builder: builder).compose([candidate]).first ?? candidate.item
        // Нагадуванню композитор ставить `wt.reminder.<день>.<HHmm>` — а зразок мусить лишитися поза диффом плану
        // (`NotificationScheduler.isManaged`), інакше наступне перепланування зняло б його до доставки.
        item.id = candidate.item.id
        return item
    }
}

extension PlanBuilder {
    func sampleCandidate(_ sample: NotificationSample, at fireAt: Date) -> Candidate {
        let glass = preferences.glassMl
        // Бракує хоч склянку: «ще 0 мл» на закритому дні в зразку нічого б не показало.
        let left = max(context.goalMl - context.countedMl, glass)
        let streak = max(context.streak.lengthEndingToday, context.streak.lengthEndingYesterday, rules.rescueMinStreak)
        let yesterday = service.dayKey(offsetDays: -1, from: today)

        func item(slot: String, floating: Bool = true, priority: NotificationPriority, category: NotificationCategory?,
                  route: NotificationTapRoute, silent: Bool = false, actionMl: Int? = nil) -> PlannedNotification {
            PlannedNotification(
                id: "debug.\(sample.type.key).\(today.rawValue).\(sample.rawValue)", type: sample.type, slot: slot,
                dayKey: today, fireAt: fireAt, isFloating: floating, priority: priority, category: category,
                tapRoute: route, interruption: silent ? .passive : .active, isSilent: silent, actionMl: actionMl
            )
        }
        func report(_ period: ReportPeriod) -> ReportDigest {
            context.reports.first { $0.period == period && $0.hasIntakes } ?? ReportDigest(
                period: period, hasIntakes: true, totalMl: 1_800, goalMl: context.goalMl, goalDays: 4, dayCount: 7,
                averageMl: 1_750, averageChangePercent: 8, weakestPart: DayPart.evening.title.lowercased(),
                longestStreak: streak, glasses: 7
            )
        }

        let copy: CopyKind
        let planned: PlannedNotification
        switch sample {
        case .reminder, .reminderFollowUp:
            let primary = sample == .reminder
            planned = item(slot: primary ? "primary" : "followUp", floating: false,
                           priority: primary ? .reminderPrimary : .reminderFollowUp, category: .reminder,
                           route: .customAmount(ml: portion))
            copy = .reminder(followUp: !primary, leftMl: left, lastIntake: context.lastIntakeAt)
        case .checkpoint:
            let part = DayPart.from(hour: service.hour(of: fireAt))
            planned = item(slot: part.key, priority: .checkpoint, category: .reminder, route: .customAmount(ml: portion))
            copy = .checkpoint(leftMl: min(left, 500), deadline: fireAt.addingTimeInterval(3_600), part: part,
                               xp: context.dayPartXp)
        case .challenge:
            planned = item(slot: "sample", floating: false, priority: .challenge, category: .reminder, route: .home)
            copy = .challenge(SurpriseSlot(kind: .glassNow, fireAt: fireAt, deadline: fireAt.addingTimeInterval(1_800),
                                           targetMl: glass, leftMl: glass))
        case .morning:
            planned = item(slot: "morning", priority: .morning, category: .glass, route: .glass)
            copy = .morning
        case .eveningClosable, .eveningStreak:
            let withStreak = sample == .eveningStreak
            planned = item(slot: withStreak ? "closableStreak" : "closable", priority: .evening, category: .glass,
                           route: .home)
            copy = .eveningClosable(leftMl: min(left, glass), streak: withStreak ? streak : nil)
        case .eveningClose:
            // Бракує більше за склянку — «Закрити норму» на весь залишок (WAT-67, §32).
            let missing = max(left, glass * 2)
            planned = item(slot: "closable", priority: .evening, category: .close, route: .home,
                           actionMl: min(missing, 600))
            copy = .eveningClosable(leftMl: missing, streak: nil)
        case .eveningSoothing:
            planned = item(slot: "soothing", priority: .evening, category: nil, route: .home)
            copy = .eveningSoothing(totalMl: context.countedMl)
        case .rescueMorning:
            planned = item(slot: "am", priority: .rescue, category: .glass, route: .freezeCard)
            copy = .rescueMorning(streak: streak)
        case .rescueEvening:
            planned = item(slot: "pm", priority: .rescue, category: nil, route: .freezeCard)
            copy = .rescueEvening(streak: streak)
        case .comebackFirst, .comebackLast:
            let number = sample == .comebackFirst ? 1 : 2
            planned = item(slot: "\(number)", priority: .morning, category: .glass, route: .home)
            copy = .comeback(number: number, giftAvailable: true)
        case .reportDay:
            let period = ReportPeriod.day(today)
            planned = item(slot: "day", priority: .report, category: nil, route: .report([period]), silent: true)
            copy = .reportDay(report(period), streak: streak)
        case .reportWeek:
            let period = service.period(.week, containing: yesterday)
            planned = item(slot: "week", priority: .report, category: nil, route: .report([period]), silent: true)
            copy = .reportWeek(report(period))
        case .reportMonth:
            let period = service.period(.month, containing: yesterday)
            planned = item(slot: "month", priority: .report, category: nil, route: .report([period]), silent: true)
            copy = .reportMonth(report(period))
        }
        return Candidate(item: planned, copy: copy, rel: 0)
    }
}
