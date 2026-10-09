import Foundation
import Core
import Persistence
import Hydration
import Gamification
import Notifications
import Widgets

// Віджети (WAT-30, SPEC-WIDGETS). Пише лише застосунок: знімок для віджетів — наприкінці кожного проходу
// перепланування, порції з віджета — тим самим шляхом, що «+склянка» зі сповіщення.

extension AppServices {
    // MARK: - Дії з віджета (§4.1, §9.2)

    /// Дія з віджета, елемента керування чи «Команд».
    ///
    /// Повертається, щойно порцію записано й знімок оновлено: після `perform()` інтенту система
    /// перезавантажує таймлайн, і кожна зайва частка секунди тут — затримка між тапом і цифрою на віджеті.
    /// Відлуння й перепланування сповіщень (~0,2 с) доходять у повернутій задачі — застосунок тримає для неї
    /// фонове завдання, а знімок із часом нагадування з нового плану приходить другим.
    @discardableResult
    public func perform(_ action: WidgetAction) async -> Task<Void, Never> {
        let now = calendar.now
        var echo: EchoContent?
        switch action {
        case let .add(ml, source):
            echo = addPortionFromOutside(ml: ml, source: source == .shortcut ? .shortcut : .widget, at: now)
        case let .undo(intakeId):
            // «Скасувати» з віджета — лише щойно додану звідти порцію: старий таймлайн не має прибирати
            // порцію, яку людина вже бачила в історії.
            guard lastWidgetAction?.intakeId == intakeId else { break }
            lastWidgetAction = nil
            _ = hydration.removeIntake(id: intakeId, at: now)
        }
        epoch &+= 1
        // Старий план — ще до порції: його нагадування для запасу не годяться, нуль поки що за темпом.
        publishWidgetSnapshot(plan: notifications.lastPlan, planIsCurrent: false)
        return Task { [weak self] in
            guard let self else { return }
            if let echo {
                await notifications.sendEcho(title: echo.title, body: echo.body, route: echo.route,
                                             intakeId: echo.intakeId, at: now)
            }
            await notifications.rescheduleNow()
        }
    }

    /// Порція ззовні — як `addGlass` зі сповіщення: черга розблокувань до й після, відлуння лише тоді, коли
    /// застосунку на екрані немає (SPEC-NOTIFICATIONS §12.1). Розблокування з холодного старту (стартовий
    /// `refresh`) — не заслуга цієї порції, тож черга спершу чиститься.
    private func addPortionFromOutside(ml: Int, source: IntakeSource, at now: Date) -> EchoContent? {
        let levelBefore = gamification.levelProgress().level
        _ = gamification.takeRecentUnlocks()
        guard let result = hydration.addIntake(amountMl: Intake.clamp(ml), source: source) else { return nil }
        let unlocks = gamification.takeRecentUnlocks()
        lastWidgetAction = WidgetSnapshot.LastAction(intakeId: result.intakeId, ml: Intake.clamp(ml), at: now)
        guard !isForeground else { return nil }
        return EchoContent.make(unlocks: unlocks, levelBefore: levelBefore,
                                levelAfter: gamification.levelProgress().level, intakeId: result.intakeId)
    }

    /// `--widget-action add:250,undo` — дії віджета для e2e: справжній домашній екран у XCUITest нестабільний.
    public func simulateWidgetActions(_ encoded: String) async {
        for step in encoded.split(separator: ",") {
            if step == "undo" {
                if let id = lastWidgetAction?.intakeId { await perform(.undo(intakeId: id)).value }
            } else if step.hasPrefix("add:"), let ml = Int(step.dropFirst(4)) {
                await perform(.add(ml: ml, source: .widget)).value
            }
        }
    }

    /// Тап по віджету — куди відкрити застосунок (§9.4).
    public func open(_ link: WidgetLink) {
        switch link {
        case .home: router.open(.home)
        case .custom: router.open(.customAmount(ml: hydration.customAmountStart()))
        case .stats: router.open(path: [.stats])
        case .progress: router.open(.progress)
        }
    }

    // MARK: - Знімок (§9.1)

    /// Новий знімок — після кожного проходу перепланування. Той самий зміст таймлайнів не перезавантажує.
    /// - Parameter planIsCurrent: план уже врахував останню дію. Ні — нуль запасу за кривою темпу, доки
    ///   перепланування не дасть справжній час нагадування.
    func publishWidgetSnapshot(plan: NotificationPlan, planIsCurrent: Bool = true) {
        let snapshot = makeWidgetSnapshot(plan: plan, planIsCurrent: planIsCurrent)
        if let published = publishedWidgetSnapshot, published.sameContent(as: snapshot) { return }
        publishedWidgetSnapshot = snapshot
        widgetStore.write(snapshot)
        widgetReloader?.reloadAll()
    }

    func makeWidgetSnapshot(plan: NotificationPlan, planIsCurrent: Bool = true) -> WidgetSnapshot {
        let now = calendar.now
        let today = calendar.today
        let profile = profile
        let day = hydration.todaySnapshot()
        let schedule = hydration.schedule(for: today)
        let portions = hydration.intakes(for: today)
            .map { WidgetSnapshot.Portion(id: $0.id, at: $0.createdAt, ml: $0.amountMl) }
            .sorted { $0.at < $1.at }
        let streak = gamification.streakSummary()
        let level = gamification.levelProgress()
        let quest = { (quest: QuestSnapshot) in
            WidgetSnapshot.Quest(title: quest.title, progressLabel: quest.progressLabel, fraction: quest.fraction,
                                 isDone: quest.isDone)
        }
        let typical = plan.typicalPortionMl > 0 ? plan.typicalPortionMl : profile.glassMl
        let reserve = HydrationReserve.make(
            portions: portions, capacityMl: HydrationReserve.capacity(typicalPortionMl: typical), now: now,
            plannedReminder: planIsCurrent ? plannedReminder(in: plan, after: portions.last?.at, on: today) : nil,
            previous: publishedWidgetSnapshot?.day == today ? publishedWidgetSnapshot?.reserve : nil,
            zero: reserveZero(goalMl: day.goalMl, schedule: schedule, typicalPortionMl: typical, day: today)
        )
        let lastAction = lastWidgetAction.flatMap { action in
            portions.contains { $0.id == action.intakeId } ? action : nil
        }
        return WidgetSnapshot(
            generatedAt: now, day: today, unitRaw: profile.volumeUnitRaw, goalMl: day.goalMl,
            totalMl: day.totalMl, countedMl: day.countedMl, portions: portions,
            schedule: WidgetSnapshot.Schedule(schedule),
            weekday: WidgetSnapshot.Schedule(wakeMinutes: profile.wakeMinutes, sleepMinutes: profile.sleepMinutes),
            weekend: profile.weekendScheduleEnabled
                ? WidgetSnapshot.Schedule(wakeMinutes: profile.weekendWakeMinutes, sleepMinutes: profile.weekendSleepMinutes)
                : nil,
            dayRhythmEnabled: profile.dayRhythmEnabled,
            homeButtons: hydration.quickAddAmounts(), glassMl: profile.glassMl,
            streak: WidgetSnapshot.Streak(current: streak.current, countsToday: streak.lastCountedDay == today),
            level: WidgetSnapshot.Level(level: level.level, xpIntoLevel: level.xpIntoLevel,
                                        xpForNextLevel: level.xpForNextLevel),
            dailyQuests: gamification.dailyQuests(at: now).map(quest),
            weeklyQuests: gamification.weeklyQuests(at: now).map(quest),
            dayPartXp: Int(Double(gamification.xp.rules.perDayPartGoal) * gamification.xp.boostMultiplier(at: now)),
            reserve: reserve, lastAction: lastAction
        )
    }

    /// Перше нагадування після останньої порції — основне, повторне чи чекпоінт, що його забрав (§9).
    private func plannedReminder(in plan: NotificationPlan, after last: Date?, on day: DayKey) -> Date? {
        guard let last else { return nil }
        return plan.items
            .filter { ($0.type == .reminder || $0.type == .checkpoint) && $0.dayKey == day && $0.fireAt > last }
            .map(\.fireAt)
            .min()
    }

    /// Де закінчується спад після порції, якщо плану немає: та сама формула першого нагадування (§6.2), що в
    /// планувальника, з частотою людини; після відсічки нагадувань і з закритою нормою — відбій.
    private func reserveZero(goalMl: Int, schedule: DaySchedule, typicalPortionMl: Int,
                             day: DayKey) -> (Date, Int) -> HydrationReserve.Zero {
        let preferences = notifications.preferences()
        let rules = notifications.rules
        let curve = schedule.curve(goalMl: goalMl)
        let cutoff = preferences.eveningEnabled
            ? min(max(preferences.eveningMinutes ?? schedule.sleepMinutes - rules.eveningLeadMinutes, schedule.wakeMinutes),
                  schedule.sleepMinutes)
            : max(schedule.wakeMinutes, schedule.sleepMinutes - rules.cutoffWithoutEveningMinutes)
        let calendar = calendar
        func date(_ minute: Double) -> Date {
            let whole = Int(minute.rounded(.up))
            return WidgetTimeline.date(of: day, minute: min(whole, 24 * 60), calendar: calendar) ?? calendar.now
        }
        let bedtime = date(Double(schedule.sleepMinutes))
        return { anchor, drunk in
            guard drunk < goalMl else { return HydrationReserve.Zero(at: bedtime, mode: .goalMet) }
            let anchorMinute = Double(calendar.minuteOfDay(anchor))
            let due: Double
            switch preferences.cadence {
            case .pace(let frequency):
                let pace = rules.pace(for: frequency)
                due = curve.nextDueMinute(anchorMinute: anchorMinute, drunkMl: drunk, portionMl: typicalPortionMl,
                                          k: pace.k, minGapMinutes: pace.minGapMinutes, maxGapMinutes: pace.maxGapMinutes)
            case .interval(let minutes):
                due = anchorMinute + Double(minutes)
            }
            guard due < Double(cutoff) else { return HydrationReserve.Zero(at: bedtime, mode: .evening) }
            let reminder = date(due)
            return HydrationReserve.Zero(at: reminder.addingTimeInterval(-HydrationReserve.reminderLead),
                                         mode: .flowing, reminderAt: reminder)
        }
    }
}
