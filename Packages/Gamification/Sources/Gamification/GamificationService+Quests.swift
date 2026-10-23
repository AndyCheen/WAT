import Foundation
import Core
import Persistence
import Metrics

/// Завдання в координаторі (WAT-63, SPEC-QUESTS): входи пікерів з історії, кеш днів і прохід.
extension GamificationService {
    /// Видача й оцінка — один прохід на подію чи `refresh`. Повертає щойно виконані.
    func runQuests(at date: Date, triggerRef: UUID?) -> [QuestInstance] {
        let day = calendar.dayKey(for: date)
        quests.ensureInstances(
            day: day, at: date,
            daily: { [unowned self] in self.dailyPickInput(day: day, at: date) },
            weekly: { [unowned self] in self.weeklyPickInput(day: day) },
            surprise: { [unowned self] in self.surprisePickInput(day: day, at: date) }
        )
        return quests.evaluate(at: date, now: max(date, calendar.now), inputs: questInputs(at: date),
                               triggerRef: triggerRef)
    }

    func questInputs(at date: Date) -> QuestInputs {
        QuestInputs(rules: makeContext(at: date), day: { [unowned self] in self.questDay($0) },
                    glassMl: profile.glassMl, unit: profile.volumeUnit)
    }

    /// Блок «ЗАВДАННЯ» головного й віджет «Прогрес» (§9).
    public func questBoard(at date: Date? = nil) -> QuestBoard {
        quests.board(at: date ?? calendar.now) { [unowned self] in self.questDay($0) }
    }

    public func dailyQuests(at date: Date? = nil) -> [QuestSnapshot] { questBoard(at: date).daily }
    public func weeklyQuests(at date: Date? = nil) -> [QuestSnapshot] { questBoard(at: date).weekly }

    /// Завдання повз пікери (`--quests`, тести). Ставити до `bootstrap()`: видача йде першою подією дня.
    public var questForcing: QuestForcing? {
        get { quests.forcing }
        set { quests.forcing = newValue }
    }

    /// Несподівані від пікера (`QuestEngine.surprisesEnabled`): під `--uitest-*` вимкнено.
    public var surprisesEnabled: Bool {
        get { quests.surprisesEnabled }
        set { quests.surprisesEnabled = newValue }
    }

    // MARK: - Дні

    /// День із запису або, до першої порції, з профілю. Кеш, бо тижневі оцінюються на кожну подію.
    func questDay(_ day: DayKey) -> QuestDay {
        if let cached = questDays[day.rawValue] { return cached }
        let goalAhead = metrics.sum(.dayGoalAhead, periodType: .day, periodKey: day.rawValue) > 0
        let isWeekend = calendar.isWeekend(day)
        let result: QuestDay
        if let log = dayLogs.existingDayLog(for: day) {
            result = QuestDay(log: log, schedule: profile.schedule(for: log, isWeekend: isWeekend),
                              goalAhead: goalAhead, calendar: calendar)
        } else {
            result = QuestDay(day: day, goalMl: profiles.currentGoalMl(on: day),
                              schedule: profile.schedule(isWeekend: isWeekend), portions: [], goalAhead: goalAhead)
        }
        questDays[day.rawValue] = result
        return result
    }

    /// Що змінила подія: день із порцією, нормою чи «норма без нагадувань».
    func noteQuestInputs(changedBy events: [RecordedMetricEvent]) {
        for event in events where Self.questDayMetrics.contains(event.name) {
            questDays[event.dayKey] = nil
        }
    }

    private static let questDayMetrics: Set<MetricKey> = [
        .intakeAdded, .intakeRemoved, .intakeRestored, .dayGoalMet, .dayGoalAhead
    ]

    // MARK: - Входи пікерів

    /// День людини: від першого дня з порцією; до першої порції — 1 (§4.1).
    func questDayNumber(_ day: DayKey) -> Int {
        guard let first = dayLogs.firstActiveDayKey(), first <= day else { return 1 }
        return calendar.daysBetween(first, day) + 1
    }

    /// 28 днів до вчора включно — більше жодне правило не дивиться.
    func questHistory(before day: DayKey) -> QuestHistory {
        let days = (1...28).map { questDay(calendar.dayKey(offsetDays: -$0, from: day)) }
        return QuestHistory(today: day, firstActive: dayLogs.firstActiveDayKey(), days: days)
    }

    func dailyPickInput(day: DayKey, at date: Date) -> DailyPickInput {
        let history = questHistory(before: day)
        let today = questDay(day)
        let keys = { [unowned self] (back: Int) in
            self.store.quests(scope: .daily, periodKey: self.calendar.dayKey(offsetDays: -back, from: day).rawValue)
                .map(\.defKey)
        }
        return DailyPickInput(
            day: day, dayNumber: questDayNumber(day), seed: mysterySeed, level: xp.progress().level,
            dayRhythm: profile.dayRhythmEnabled, remindersActive: remindersActive(), schedule: today.schedule,
            goalMl: today.goalMl, glassMl: profile.glassMl,
            // Подія з минулого дня (повернута порція) видає завдання того дня — з його початку.
            issueMinute: calendar.dayKey(for: date) == day ? calendar.minuteOfDay(date) : 0,
            goalMetYesterday: history.goalMetYesterday, goalDays7: history.goalDays(7),
            yesterdayKeys: Set(keys(1)), recentKeys: (1...DailyQuestPicker.recentDays).flatMap(keys),
            goalMedianMinute: history.goalMedianMinute, weakSpots: history.weakSpots(today: today.schedule),
            weakBlock: profile.dayRhythmEnabled ? history.weakBlock(blockCount: today.blocks.count, seed: mysterySeed) : nil,
            rules: xp.rules
        )
    }

    func weeklyPickInput(day: DayKey) -> WeeklyPickInput {
        let history = questHistory(before: day)
        let weekStart = calendar.weekStart(of: day)
        let lastWeek = calendar.weekKey(for: calendar.date(from: calendar.dayKey(offsetDays: -7, from: weekStart)))
        let shares = history.goalShares
        return WeeklyPickInput(
            week: calendar.weekKey(for: calendar.date(from: day)), todayIndex: day.weekdayIndex,
            isFirstWeek: (history.firstActive ?? day) >= weekStart,
            seed: mysterySeed, level: xp.progress().level, dayRhythm: profile.dayRhythmEnabled,
            goalDaysPerFullWeek: history.goalDaysPerFullWeek,
            lastWeek: store.quests(scope: .weekly, periodKey: lastWeek.rawValue).map { ($0.defKey, $0.isDone) },
            goalDays14: history.goalDays(14), weekendGoalShare: shares.weekend, weekdayGoalShare: shares.weekday,
            halfByDays7: history.halfByDays7, weakSpots: history.weakSpots(today: questDay(day).schedule),
            goalMedianMinute: history.goalMedianMinute, rules: xp.rules
        )
    }

    /// Входи `SurprisePicker` (QUESTS-PLAN §3.4) — лише на сьогодні: несподіване планується в першу дію дня, а подія
    /// з минулого дня (повернута порція) його не планує.
    func surprisePickInput(day: DayKey, at date: Date) -> SurprisePickInput? {
        guard day == calendar.today, calendar.dayKey(for: date) == day else { return nil }
        let today = questDay(day)
        let from = calendar.dayKey(offsetDays: -SurpriseRules.historyDays, from: day)
        let history = store.quests(scope: .adhoc, periodKey: nil).compactMap { instance -> SurpriseRecord? in
            guard let instanceDay = QuestEngine.day(of: instance), instanceDay >= from, instanceDay < day else { return nil }
            return SurpriseRecord(day: instanceDay, key: instance.defKey, state: instance.state,
                                  blockIndex: instance.blockIndex)
        }
        return SurprisePickInput(
            day: day, week: calendar.weekKey(for: date), dayNumber: questDayNumber(day), seed: mysterySeed,
            perWeek: profile.surpriseQuestsPerWeek, dayRhythm: profile.dayRhythmEnabled, schedule: today.schedule,
            goalMl: today.goalMl, issueMinute: calendar.minuteOfDay(date), goalMetToday: today.goalMet,
            history: history, signals: surpriseSignals(), quietMinutes: quietMinutes(day), rules: xp.rules
        )
    }

    // MARK: - Нагорода

    /// XP — з інстансу (зафіксований при видачі, §8), у архівних — з визначення. Буст і загальний множник —
    /// у `XPEngine`, серія завдань не множить.
    func awardQuestXP(_ completed: [QuestInstance], at date: Date) {
        for quest in completed {
            guard let definition = QuestCatalog.definition(quest.defKey) else { continue }
            let amount = quest.rewardXp > 0 ? quest.rewardXp : definition.legacyXp
            xp.award(amount: amount, reason: .questCompleted, refId: quest.id, at: date)
            metrics.record(MetricEvent(
                name: .questCompleted, value: 1, occurredAt: date, sourceRef: quest.id,
                payload: ["key": quest.defKey]
            ))
            if definition.scope == .weekly {
                metrics.record(MetricEvent(
                    name: .weeklyQuestCompleted, value: 1, occurredAt: date, sourceRef: quest.id,
                    payload: ["key": quest.defKey]
                ))
            }
            if definition.scope == .adhoc {
                metrics.record(MetricEvent(
                    name: .surpriseQuestCompleted, value: 1, occurredAt: date, sourceRef: quest.id,
                    payload: ["key": quest.defKey]
                ))
                // ⚡ один на інстанс: «відкат → знову виконано» другого не дає, а виданий приз не відкликається (§6.5).
                grantPrize(key: RewardCatalog.boostKey, source: .quest, ref: quest.id, at: date)
            }
        }
    }
}
