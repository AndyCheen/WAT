import Foundation
import Core
import Persistence

/// Планувальник сповіщень — **чиста функція** (SPEC-NOTIFICATIONS §16.2).
///
/// Код застосунку в момент доставки не виконується (лише локальні сповіщення, §16.1), тож
/// план складається наперед **з припущенням, що користувач більше нічого не робить**, а будь-яка
/// зміна стану його перебудовує. Між двома діями стан не змінюється, тому зміст, порахований
/// заздалегідь, у момент доставки правильний.
///
/// Порядок: горизонт → фіксовані типи (ранок, вечір, порятунок, повернення) → чекпоінти
/// частин доби → ланцюги нагадувань (зливаються з чекпоінтами) → конфлікти (≥ 30 хв, пріоритети §13.3) → денний ліміт → бюджет 64 → тексти.
public enum NotificationPlanner {
    public static func plan(
        context: NotificationContext,
        preferences: NotificationPreferences,
        journal: NotificationJournal = .empty,
        rules: NotificationRules = .default
    ) -> NotificationPlan {
        PlanBuilder(context: context, preferences: preferences, journal: journal, rules: rules).build()
    }
}

/// Кандидат до тексту: що це, коли, і з чого потім складеться текст.
struct Candidate {
    var item: PlannedNotification
    var copy: CopyKind
    /// Зсув дня від сьогодні — для вставок контексту.
    var rel: Int
}

/// Ситуація, з якої `TextComposer` складе заголовок і текст.
enum CopyKind: Equatable {
    case reminder(followUp: Bool, leftMl: Int, lastIntake: Date?)
    case morning
    case eveningClosable(leftMl: Int, streak: Int?)
    case eveningSoothing(totalMl: Int)
    case rescueEvening(streak: Int)
    case rescueMorning(streak: Int)
    case comeback(number: Int, giftAvailable: Bool)
    case checkpoint(leftMl: Int, deadline: Date, part: DayPart, xp: Int)
}

/// День горизонту: `rel` — від сьогодні, `sinceAction` — від дня останньої дії (§13.5).
struct PlanningDay {
    let day: DayKey
    let rel: Int
    let sinceAction: Int
    let frame: DayFrame
}

struct PlanBuilder {
    let context: NotificationContext
    let preferences: NotificationPreferences
    let journal: NotificationJournal
    let rules: NotificationRules
    let service: CalendarService
    let today: DayKey
    let portion: Int
    let lastActionDay: DayKey
    let projection: StreakProjection

    init(context: NotificationContext, preferences: NotificationPreferences,
         journal: NotificationJournal, rules: NotificationRules) {
        self.context = context
        self.preferences = preferences
        self.journal = journal
        self.rules = rules
        let service = CalendarService(clock: FixedClock(now: context.now, timeZone: context.timeZone))
        self.service = service
        today = service.today
        portion = TypicalPortion.compute(context.portionHistoryMl, glassMl: preferences.glassMl, rules: rules)

        // Остання дія — порція, відкриття застосунку чи відповідь на сповіщення (рішення від 04.10.2026).
        let actions = [context.lastIntakeAt, context.lastInteractionAt, journal.lastResponse].compactMap { $0 }
        lastActionDay = actions.max().map { service.dayKey(for: $0) } ?? service.today
        projection = StreakProjection(input: context.streak, minStreak: rules.rescueMinStreak)
    }

    var now: Date { context.now }
    var earliest: Date { now.addingTimeInterval(rules.minLeadSeconds) }

    func build() -> NotificationPlan {
        guard preferences.isEnabled else { return makePlan([]) }

        var accepted: [Candidate] = []
        for day in planningDays() {
            let fixed = fixedCandidates(for: day)
            let checkpoints = checkpoints(for: day)
            let chain = reminderChain(for: day, checkpoints: checkpoints)
            let shown = journal.shown(on: day.day, before: now)
            let resolved = ConflictResolver(spacing: TimeInterval(rules.minSpacingMinutes * 60), frame: day.frame)
                .resolve(fixed + checkpoints + chain, shown: shown.map(\.fireAt))
            accepted += DailyCap.apply(resolved, shownCount: shown.count, cap: rules.dailyCap)
        }

        // Бюджет iOS — 64 запити; найближчі важливіші за далекі (§16.2).
        let budget = rules.maxPending - rules.echoReserve
        let kept = accepted.sorted { $0.item.fireAt < $1.item.fireAt }.prefix(budget)
        let composer = TextComposer(builder: self)
        return makePlan(composer.compose(Array(kept)))
    }

    private func makePlan(_ items: [PlannedNotification]) -> NotificationPlan {
        NotificationPlan(items: items, generatedAt: now, typicalPortionMl: portion,
                         lastActionDay: lastActionDay, glassMl: preferences.glassMl)
    }

    // MARK: - Горизонт (§16.2, §13.5)

    /// Сьогодні + 2 дні, плюс дні повернення +3 і +7 від останньої дії. Неактивність «вшита» в
    /// план: що далі від останньої дії, то менше в ньому лишається (§13.5).
    func planningDays() -> [PlanningDay] {
        let sinceToday = max(0, service.daysBetween(lastActionDay, today))
        var rels = Array(0...rules.horizonDays)
        for offset in rules.comebackOffsets {
            let rel = offset - sinceToday
            if rel > rules.horizonDays { rels.append(rel) }
        }
        return rels.map { rel in
            let day = service.dayKey(offsetDays: rel, from: today)
            let frame = DayFrame(day: day, calendar: service, goalMl: context.goalMl,
                                 preferences: preferences, rules: rules)
            return PlanningDay(day: day, rel: rel, sinceAction: sinceToday + rel, frame: frame)
        }
    }

    /// Пауза «Не сьогодні» гасить мотиваційні типи до півночі (§6.4), порятунок — ні.
    func isPaused(_ day: PlanningDay) -> Bool {
        preferences.pausedUntil.map { $0 > day.frame.dayStart } ?? false
    }

    func intakes(on day: PlanningDay) -> [Date] {
        day.rel == 0 ? context.intakesToday.filter { service.dayKey(for: $0) == day.day } : []
    }

    func counted(on day: PlanningDay) -> Int { day.rel == 0 ? context.countedMl : 0 }

    /// Порції дня в хвилинах доби — для цілей частин доби. Майбутні дні — порожні: план
    /// припускає, що користувач більше нічого не робить.
    func portions(on day: PlanningDay) -> [TimedPortion] {
        guard day.rel == 0 else { return [] }
        return context.portionsToday
            .filter { service.dayKey(for: $0.at) == day.day }
            .map { TimedPortion(minute: Int(day.frame.minute(of: $0.at)), ml: $0.ml) }
    }

    // MARK: - Фіксовані типи

    func fixedCandidates(for day: PlanningDay) -> [Candidate] {
        // Дні повернення замінюють ранкову склянку й більше нічого не мають (§12.1).
        if let index = rules.comebackOffsets.firstIndex(of: day.sinceAction) {
            guard preferences.comebackEnabled, let comeback = comeback(day, number: index + 1) else { return [] }
            return [comeback]
        }
        switch day.sinceAction {
        case 0, 1: return [morning(day), evening(day)].compactMap { $0 }
        case 2: return [morning(day)].compactMap { $0 }   // день без жодної дії — одне повідомлення
        default: return []
        }
    }

    /// Ранкова склянка (§7) або ранковий порятунок серії, злитий із нею (§12.1, §13.3).
    func morning(_ day: PlanningDay) -> Candidate? {
        let frame = day.frame
        guard let at = frame.place(frame.morningAt, limit: frame.sleep), at > earliest else { return nil }

        if preferences.rescueEnabled, context.readyFreezes > 0, let streak = projection.morningRescue(on: day.rel) {
            let item = PlannedNotification(
                id: "wt.rescue.\(day.day.rawValue).am", type: .rescue, slot: "am", dayKey: day.day, fireAt: at,
                isFloating: true, priority: .rescue, category: .glass, tapRoute: .freezeCard
            )
            return Candidate(item: item, copy: .rescueMorning(streak: streak), rel: day.rel)
        }

        guard preferences.morningEnabled, intakes(on: day).isEmpty else { return nil }
        let item = PlannedNotification(
            id: "wt.morning.\(day.day.rawValue)", type: .morning, slot: "morning", dayKey: day.day, fireAt: at,
            isFloating: true, priority: .morning, category: .glass,
            // Етап A: шторки «Склянка» ще немає — тап веде в «Інше» з типовою порцією (§17).
            tapRoute: .customAmount(ml: portion)
        )
        return Candidate(item: item, copy: .morning, rel: day.rel)
    }

    /// Вечірній підсумок — ситуації §8 згори вниз. Ситуація 3 — порятунок серії (тип 7).
    func evening(_ day: PlanningDay) -> Candidate? {
        let frame = day.frame
        let drank = counted(on: day)
        guard drank < context.goalMl else { return nil }                                   // 1
        guard let at = frame.place(frame.eveningAt, limit: frame.sleep), at > earliest else { return nil }

        let missing = context.goalMl - drank
        let closable = min(rules.closableMultiplier * Double(portion), Double(rules.eveningCapMl))
        let paused = isPaused(day)
        let eveningId = "wt.evening.\(day.day.rawValue)"

        if Double(missing) <= closable {                                                     // 2
            guard preferences.eveningEnabled, !paused else { return nil }
            let streak = projection.continuingStreak(on: day.rel)
            let item = PlannedNotification(
                id: eveningId, type: .evening, slot: streak == nil ? "closable" : "closableStreak",
                dayKey: day.day, fireAt: at, isFloating: true, priority: .evening, category: .glass, tapRoute: .home
            )
            return Candidate(item: item, copy: .eveningClosable(leftMl: missing, streak: streak), rel: day.rel)
        }

        // Порятунок має власний вимикач і не зважає на паузу: він не про «пий», а про
        // «не втрать зроблене» (§12.1).
        if preferences.rescueEnabled, context.readyFreezes > 0, let streak = projection.eveningRescue(on: day.rel) { // 3
            let item = PlannedNotification(
                id: "wt.rescue.\(day.day.rawValue).pm", type: .rescue, slot: "pm", dayKey: day.day, fireAt: at,
                isFloating: true, priority: .rescue, category: nil, tapRoute: .freezeCard
            )
            return Candidate(item: item, copy: .rescueEvening(streak: streak), rel: day.rel)
        }

        // 5: за день жодної порції — нічого: застосунком сьогодні не користуються.
        guard preferences.eveningEnabled, !paused, !intakes(on: day).isEmpty else { return nil }       // 4
        let item = PlannedNotification(
            id: eveningId, type: .evening, slot: "soothing", dayKey: day.day, fireAt: at,
            isFloating: true, priority: .evening, category: nil, tapRoute: .home
        )
        return Candidate(item: item, copy: .eveningSoothing(totalMl: drank), rel: day.rel)
    }

    /// Повернення після перерви — у звичний момент першої порції (§12.1).
    func comeback(_ day: PlanningDay, number: Int) -> Candidate? {
        let frame = day.frame
        let wake = Int(frame.curve.wakeMinutes)
        let latest = max(wake, Int(frame.minute(of: frame.cutoff)) - 1)
        let usual = Self.median(context.firstIntakeMinutes) ?? wake
        let minute = min(max(usual, wake), latest)
        guard let at = frame.place(frame.date(minute: Double(minute)), limit: frame.sleep), at > earliest else { return nil }

        let giftAvailable = number == rules.comebackOffsets.count && context.lastComebackGiftAt.map {
            service.daysBetween(service.dayKey(for: $0), day.day) >= context.comebackCooldownDays
        } ?? true
        let item = PlannedNotification(
            id: "wt.comeback.\(day.day.rawValue).\(number)", type: .comeback, slot: "\(number)", dayKey: day.day,
            fireAt: at, isFloating: true, priority: .morning, category: .glass, tapRoute: .home
        )
        return Candidate(item: item, copy: .comeback(number: number, giftAvailable: giftAvailable), rel: day.rel)
    }

    // MARK: - Чекпоінти частин доби (§9)

    /// «До 12:00 — ще 150 мл» за 45 хв до кінця частини доби, якщо її ціль ще не закрита, але
    /// закрити реально. Вечір чекпоінта не має: його кінець — відбій, цю роль виконує вечірній
    /// підсумок; тому й чекпоінт пізніше за відсічку нагадувань не планується.
    func checkpoints(for day: PlanningDay) -> [Candidate] {
        guard preferences.checkpointsEnabled, day.sinceAction <= 1, !isPaused(day),
              counted(on: day) < context.goalMl else { return [] }
        let frame = day.frame
        let portions = portions(on: day)
        let lag = Double(portion) * rules.checkpointLagShare
        let closable = rules.closableMultiplier * Double(portion)

        return frame.curve.goalBlocks(minSegmentMinutes: rules.minSegmentMinutes).dropLast().compactMap { block in
            let deadline = frame.date(minute: Double(block.toMinute))
            let nominal = frame.date(minute: Double(block.toMinute - rules.checkpointLeadMinutes))
            guard let at = frame.place(nominal, limit: min(deadline, frame.cutoff)), at > earliest else { return nil }

            let drunk = block.drunkMl(of: portions)
            let left = block.targetMl - drunk
            // 1. Відставання всередині частини ≥ ½P: хто п'є рівномірно, закриє її сам.
            // 2. Бракує 50 мл … 2·P: недосяжний чекпоінт лише фіксує невдачу, а загальне
            //    відставання й так веде нагадування.
            let behind = frame.curve.target(fromMinute: Double(block.fromMinute), toMinute: frame.minute(of: at)) - Double(drunk)
            guard behind >= lag, left >= rules.checkpointMinLeftMl, Double(left) <= closable else { return nil }

            let boosted = context.boostExpiresAt.map { $0 > at } ?? false
            let part = block.deadlinePart
            let item = PlannedNotification(
                id: "wt.checkpoint.\(day.day.rawValue).\(part.key)", type: .checkpoint, slot: part.key, dayKey: day.day,
                fireAt: at, isFloating: true, priority: .checkpoint, category: .reminder,
                tapRoute: .customAmount(ml: portion)
            )
            let copy = CopyKind.checkpoint(leftMl: left, deadline: deadline, part: part,
                                           xp: context.dayPartXp * (boosted ? 2 : 1))
            return Candidate(item: item, copy: copy, rel: day.rel)
        }
    }

    /// Чекпоінт, що забирає собі основне нагадування: основне у вікні `[чекпоінт − 45, чекпоінт + 30]`
    /// не надсилається, бо в чекпоінті конкретніший текст — дедлайн і об'єм (§9).
    private func checkpoint(absorbing primary: Date, in checkpoints: [Candidate]) -> Candidate? {
        checkpoints.first {
            let at = $0.item.fireAt
            return primary >= at.addingTimeInterval(-TimeInterval(rules.checkpointMergeBeforeMinutes * 60))
                && primary <= at.addingTimeInterval(TimeInterval(rules.checkpointMergeAfterMinutes * 60))
        }
    }

    // MARK: - Нагадування (§6.2)

    /// Ланцюг: основне → повторне (+30) → основне (+120) → повторне (+30), далі пауза до порції
    /// або відкриття застосунку. Простими словами — нагадуємо, коли від останньої порції минуло
    /// стільки, що за темпом уже настав час наступної.
    ///
    /// Основне, що збігається з чекпоінтом, зливається з ним: чекпоінт займає місце основного в
    /// ланцюгу, повторне й наступний блок рахуються від чекпоінта (§9).
    func reminderChain(for day: PlanningDay, checkpoints: [Candidate] = []) -> [Candidate] {
        guard preferences.remindersEnabled, day.sinceAction <= 1, !isPaused(day) else { return [] }
        let frame = day.frame
        let drank = counted(on: day)
        guard drank < context.goalMl else { return [] }

        // Якір — остання порція сьогодні, а без порцій — підйом: інакше той, хто ще нічого не
        // записав, лишився б без нагадувань (§6.1, висновок 3).
        let todayIntakes = intakes(on: day)
        let anchor = todayIntakes.max() ?? frame.wake
        let anchorMinute = frame.minute(of: anchor)

        var first: Double
        switch preferences.cadence {
        case .pace(let frequency):
            let pace = rules.pace(for: frequency)
            // `max(A, E(L))`: старий дефіцит — справа вечірнього підсумку, нагадування стежить
            // лише за поточним ритмом. З просто `A` нарада давала 8 нагадувань замість 4 (§6.2).
            let base = max(Double(drank), frame.curve.expected(atMinute: anchorMinute))
            let low = anchorMinute + Double(pace.minGapMinutes)
            let high = anchorMinute + Double(pace.maxGapMinutes)
            if let reach = frame.curve.minute(reaching: base + pace.k * Double(portion)), reach <= high {
                first = max(low, reach)
            } else {
                first = high
            }
        case .interval(let minutes):
            first = anchorMinute + Double(minutes)
        }

        var start = frame.date(minute: frame.ceilToMinute(first))
        if day.rel == 0 {
            // Відкриття застосунку чи undo — перше нагадування не раніше ніж через 30 хв;
            // «Нагадати за годину» — одне основне через 60 хв (§6.2, §6.4).
            let notBefore = [
                context.lastInteractionAt?.addingTimeInterval(TimeInterval(rules.interactionDelayMinutes * 60)),
                journal.lastSnooze?.addingTimeInterval(TimeInterval(rules.snoozeDelayMinutes * 60))
            ].compactMap { $0 }.max()
            if let notBefore, notBefore > start {
                start = frame.date(minute: frame.ceilToMinute(frame.minute(of: notBefore)))
            }
        }
        guard start < frame.cutoff else { return [] }

        let followUp = TimeInterval(rules.followUpMinutes * 60)
        let backoff = TimeInterval(rules.blockBackoffMinutes * 60)
        let lastIntake = todayIntakes.max()
        var chain: [Candidate] = []

        func append(_ nominal: Date, primary: Bool) {
            // Тихий період зсуває момент на свій кінець; кілька зсунутих в одну точку зливаються.
            guard let at = frame.place(nominal, limit: frame.cutoff),
                  !chain.contains(where: { $0.item.fireAt == at }), at > earliest else { return }
            let item = PlannedNotification(
                id: "", type: .reminder, slot: primary ? "primary" : "followUp", dayKey: day.day,
                fireAt: at, isFloating: false,
                priority: primary ? .reminderPrimary : .reminderFollowUp,
                category: .reminder, tapRoute: .customAmount(ml: portion)
            )
            let copy = CopyKind.reminder(followUp: !primary, leftMl: context.goalMl - drank, lastIntake: lastIntake)
            chain.append(Candidate(item: item, copy: copy, rel: day.rel))
        }

        var next = start
        for _ in 0..<rules.maxUnansweredBlocks {
            // Блок: основне → повторне (+30) → наступне основне (+120 від повторного).
            var blockStart = next
            if let placed = frame.place(next, limit: frame.cutoff),
               let checkpoint = checkpoint(absorbing: placed, in: checkpoints) {
                blockStart = checkpoint.item.fireAt
            } else {
                append(next, primary: true)
            }
            if preferences.followUpEnabled { append(blockStart.addingTimeInterval(followUp), primary: false) }
            next = blockStart.addingTimeInterval(followUp + backoff)
        }
        return chain
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
