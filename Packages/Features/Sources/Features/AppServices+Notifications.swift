import Foundation
import Core
import Persistence
import Metrics
import Hydration
import Insights
import Gamification
import Notifications

/// Сповіщення в композиційному корені: збирання контексту для планувальника й обробка відповідей.
///
/// Пакет `Notifications` не бачить ні води, ні гейміфікації (§16.10) — усе, що йому треба,
/// приходить звідси простим значенням, а дія «+склянка» додає порцію тут, через `HydrationService`.
extension AppServices {

    // MARK: - Контекст (§16.10)

    /// Читає `DayLog` за 45 днів і порції лише за 14 — не всю історію: планувальник має
    /// вкладатися в кілька мілісекунд (§16.3).
    func makeNotificationContext() -> NotificationContext {
        let now = calendar.now
        let today = calendar.today
        let logs = dayLogs.dayLogs(from: calendar.dayKey(offsetDays: -45, from: today), to: today)
        let active = logs.filter { $0.entriesCount > 0 }
        let portionsFrom = calendar.dayKey(offsetDays: -(notifications.rules.portionHistoryDays - 1), from: today).rawValue

        let portions = active
            .filter { $0.dayKey >= portionsFrom }
            .flatMap { ($0.intakes ?? []).filter { !$0.isDeleted }.map(\.amountMl) }
        let firstMinutes = active.suffix(14).compactMap(\.firstIntakeAt).map { date -> Int in
            let parts = calendar.calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }

        let facts = gamification.streakFacts(at: now)
        let rules = gamification.xp.rules
        let todayIntakes = dayLogs.activeIntakes(for: today)
        let reports = NotificationPlanner.reportPeriods(
            now: now, timeZone: calendar.calendar.timeZone, preferences: notifications.preferences(), rules: notifications.rules
        ).map(reportDigest)
        return NotificationContext(
            now: now,
            timeZone: calendar.calendar.timeZone,
            goalMl: hydration.currentGoal(),
            countedMl: hydration.todaySnapshot().countedMl,
            intakesToday: todayIntakes.map(\.createdAt),
            portionsToday: todayIntakes.map { Portion(at: $0.createdAt, ml: $0.amountMl) },
            lastIntakeAt: active.compactMap(\.lastIntakeAt).max(),
            lastInteractionAt: notifications.settings.lastInteractionAt,
            portionHistoryMl: portions,
            firstIntakeMinutes: firstMinutes,
            streak: StreakInput(
                countedToday: facts.countedToday, countedYesterday: facts.countedYesterday,
                countedDayBefore: facts.countedDayBefore, lengthEndingToday: facts.lengthEndingToday,
                lengthEndingYesterday: facts.lengthEndingYesterday, lengthEndingDayBefore: facts.lengthEndingDayBefore
            ),
            readyFreezes: gamification.streakSummary().freezeTokens,
            boostExpiresAt: gamification.prizes(at: now).first { $0.key == RewardCatalog.boostKey && $0.state == .active }?.expiresAt,
            lastComebackGiftAt: gamification.lastComebackGiftAt(),
            lastBounceBackDay: gamification.lastBounceBackDay(),
            quests: questHints(at: now),
            bounceBackXp: rules.perBounceBack,
            dayPartXp: rules.perDayPartGoal,
            reports: reports,
            bounceBackMinStreak: rules.bounceBackMinStreak,
            bounceBackCooldownDays: rules.bounceBackCooldownDays,
            comebackCooldownDays: rules.comebackCooldownDays
        )
    }

    /// Числа звіту для тексту сповіщення (§11.2): рахує `Insights`, формулює `Notifications`.
    private func reportDigest(_ period: ReportPeriod) -> ReportDigest {
        let report = insights.report(for: period, withThought: false)
        return ReportDigest(
            period: period, hasIntakes: report.hasData, totalMl: report.totalMl, goalMl: report.goalMl,
            goalDays: report.goalDays, dayCount: report.days.count, averageMl: report.averageMl,
            averageChangePercent: report.averageChangePercent, weakestPart: report.weakestBlock?.title,
            longestStreak: report.longestStreak?.length ?? 0, glasses: report.glasses
        )
    }

    /// Підказки для вставок контексту (§12.2) і ранкового варіанта тексту (§14.2).
    private func questHints(at now: Date) -> QuestHints {
        func metricKey(_ quest: QuestSnapshot) -> MetricKey? {
            guard case .metric(let key, _, _) = QuestCatalog.definition(quest.key)?.rule.source else { return nil }
            return key
        }
        let daily = gamification.dailyQuests(at: now).filter { !$0.isDone }
        var hints = QuestHints()
        hints.morningQuestActive = daily.contains { metricKey($0) == .partMorning }
        hints.oneEntryLeftTitle = daily.first { metricKey($0) == .intakeCount && $0.target - $0.progress == 1 }?.title

        // Неділя: тижневе завдання «норма N днів» закривається сьогоднішньою нормою.
        let isSunday = calendar.calendar.component(.weekday, from: now) == 1
        if isSunday, !hydration.todaySnapshot().goalMet,
           let weekly = gamification.weeklyQuests(at: now).first(where: {
               !$0.isDone && metricKey($0) == .dayGoalMet && $0.target - $0.progress == 1
           }) {
            hints.weeklyClosesToday = QuestHints.WeeklyHint(title: weekly.title, xp: weekly.rewardXp)
        }
        return hints
    }

    // MARK: - Відповіді (§6.4, §16.4)

    /// Дія чи тап по сповіщенню. Дії без `.foreground` обробляються у фоні: порція →
    /// `commit()` → журнал → перепланування → за потреби відлуння.
    public func handleNotificationResponse(_ response: NotificationResponseInfo) async {
        let now = calendar.now
        switch response.action {
        case .addGlass:
            if let echo = addGlass(from: response) {
                await notifications.sendEcho(title: echo.title, body: echo.body, route: echo.route,
                                             intakeId: echo.intakeId, at: now)
            }
        case .otherAmount:
            notifications.recordOpen(identifier: response.identifier, at: now)
            router.open(.customAmount(ml: response.portionMl ?? profile.glassMl))
        case .snooze:
            notifications.snooze(identifier: response.identifier, at: now)
        case .pause:
            notifications.pause(identifier: response.identifier, at: now)
        case .open:
            notifications.recordOpen(identifier: response.identifier, at: now)
            router.open(response.route)
        case .dismiss:
            break
        }
        epoch &+= 1
        await notifications.rescheduleNow()
    }

    /// «+склянка» з сповіщення. Повторна відповідь на те саме сповіщення (подвійний тап,
    /// повторна доставка відповіді) порцію не дублює — журнал уже має відповідь.
    /// Повертає відлуння, якщо порція щось відкрила, а застосунку на екрані немає.
    private func addGlass(from response: NotificationResponseInfo) -> EchoContent? {
        guard !notifications.isIntakeResponded(response.identifier) else { return nil }
        let amount = Intake.clamp(response.glassMl ?? profile.glassMl)
        let levelBefore = gamification.levelProgress().level
        // Холодний старт від дії: черга могла набратися зі стартового `refresh`.
        _ = gamification.takeRecentUnlocks()
        notifications.beginAttribution(identifier: response.identifier)
        let result = hydration.addIntake(amountMl: amount, source: .notification)
        notifications.endAttribution()
        let unlocks = gamification.takeRecentUnlocks()
        guard let result, !isForeground else { return nil }
        return EchoContent.make(unlocks: unlocks, levelBefore: levelBefore,
                                levelAfter: gamification.levelProgress().level, intakeId: result.intakeId)
    }

    /// `--notification-tap <тип>` — імітує тап для e2e: реальні сповіщення в симуляторі
    /// нестабільні (§16.11).
    public func simulateNotificationTap(_ type: NotificationType) {
        // План рахується асинхронно — на старті його ще немає, тож `P` береться з контексту.
        let portion = TypicalPortion.compute(makeNotificationContext().portionHistoryMl, glassMl: profile.glassMl)
        switch type {
        case .reminder, .checkpoint: router.open(.customAmount(ml: portion))
        case .morning: router.open(.glass)
        case .rescue: router.open(.freezeCard)
        case .echo: router.open(.progress)
        // Звіт — за минулий тиждень: у демо-історії він повний (§11.3).
        case .report: router.open(.report([calendar.period(.week, containing: calendar.dayKey(offsetDays: -7, from: calendar.today))]))
        default: router.open(.home)
        }
    }
}

/// Відлуння розблокувань (§12.1, тип 8): одне сповіщення на дію, найважливіше спершу.
struct EchoContent: Equatable {
    let title: String
    let body: String
    let route: NotificationTapRoute
    let intakeId: UUID

    static func make(unlocks: RecentUnlocks, levelBefore: Int, levelAfter: Int, intakeId: UUID) -> EchoContent? {
        if unlocks.comebackGift != nil {
            let text = EchoText.comebackGift
            return EchoContent(title: text.title, body: text.body, route: .boostCard, intakeId: intakeId)
        }
        if levelAfter > levelBefore {
            let text = EchoText.level(levelAfter)
            return EchoContent(title: text.title, body: text.body, route: .progress, intakeId: intakeId)
        }
        switch unlocks.achievements.count {
        case 0: break
        case 1:
            let text = EchoText.achievement(unlocks.achievements[0].title)
            return EchoContent(title: text.title, body: text.body,
                               route: .achievement(key: unlocks.achievements[0].key), intakeId: intakeId)
        default:
            let text = EchoText.achievements(count: unlocks.achievements.count)
            return EchoContent(title: text.title, body: text.body, route: .progress, intakeId: intakeId)
        }
        if let xp = unlocks.bounceBackXp {
            let text = EchoText.bounceBack(xp: xp)
            return EchoContent(title: text.title, body: text.body, route: .home, intakeId: intakeId)
        }
        return nil
    }
}
