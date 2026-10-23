import Foundation
import Core
import Persistence
import Metrics

/// Завдання повз пікери — DEBUG-прапорець `--quests` і тести (QUESTS-PLAN §1.11): e2e не мають залежати від зерна
/// профілю. Параметри (T, блок) резолвляться, як у пікера, але без відбору: завдання видається завжди.
public struct QuestForcing: Sendable, Equatable {
    public var daily: [String]
    /// Ключ і N.
    public var weekly: [(key: String, count: Int?)]

    public init(daily: [String] = [], weekly: [(key: String, count: Int?)] = []) {
        self.daily = daily
        self.weekly = weekly
    }

    /// `daily:daily.wakeGlass,daily.glasses;weekly:weekly.goalDays=5,weekly.wakeGlassDays=5`. Невідомі ключі
    /// пропускаються; без жодного відомого — `nil`.
    public init?(argument: String) {
        var forcing = QuestForcing()
        for section in argument.split(separator: ";") {
            let parts = section.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let items = parts[1].split(separator: ",").map { $0.split(separator: "=").map(String.init) }
            switch parts[0] {
            case "daily":
                forcing.daily = items.compactMap(\.first).filter { QuestCatalog.definition($0)?.scope == .daily }
            case "weekly":
                forcing.weekly = items.compactMap { item in
                    guard let key = item.first, QuestCatalog.definition(key)?.scope == .weekly else { return nil }
                    return (key, item.count > 1 ? Int(item[1]) : nil)
                }
            default:
                continue
            }
        }
        guard !forcing.daily.isEmpty || !forcing.weekly.isEmpty else { return nil }
        self = forcing
    }

    public static func == (lhs: QuestForcing, rhs: QuestForcing) -> Bool {
        lhs.daily == rhs.daily && lhs.weekly.map(\.key) == rhs.weekly.map(\.key)
            && lhs.weekly.map(\.count) == rhs.weekly.map(\.count)
    }
}

/// Що потрібно для оцінки умов, крім самих інстансів. Збирає `GamificationService`.
@MainActor
struct QuestInputs {
    /// Для архівних правил шини.
    let rules: RuleContext
    let day: (DayKey) -> QuestDay
    let glassMl: Int
    let unit: VolumeUnit
}

/// Щоденні та тижневі завдання: видача пікерами, прогрес за умовами дня, закриття, прострочення й відкат.
@MainActor
public final class QuestEngine {
    private let store: GamificationStoreProtocol
    private let calendar: CalendarService

    public var forcing: QuestForcing?
    /// Періоди, для яких видачу вже перевірено: подій кілька на порцію, а пошук інстансів — запит у базу.
    /// Тижневий — разом із днем: у понеділок завдань могло не бути (не відкривали), а у вівторок — уже видаються.
    private var checkedPeriods: Set<String> = []
    /// Інстанси за ключем періоду: оцінка йде на кожну подію порції, а вибірка SwiftData помітна на
    /// `PerformanceTests`. Інстанси створює лише цей рушій, тож кеш поповнюється в `insert`.
    private var periodCache: [String: [QuestInstance]] = [:]

    public init(store: GamificationStoreProtocol, calendar: CalendarService) {
        self.store = store
        self.calendar = calendar
    }

    // MARK: - Видача

    /// Видає завдання дня й тижня, якщо їх ще немає: першою подією дня (§4) і тижня (§5). Інстанси архівних
    /// ключів, що вже є за сьогодні чи тиждень, лишаються, і нових поверх них не додаємо (§3.7).
    func ensureInstances(day: DayKey, at date: Date, daily: () -> DailyPickInput, weekly: () -> WeeklyPickInput) {
        let dayKey = day.rawValue
        if checkedPeriods.insert("day|\(dayKey)").inserted, instances(periodKey: dayKey).isEmpty {
            let input = daily()
            let picks = forcing.map { forced in
                forced.daily.compactMap { QuestCatalog.definition($0).map { DailyQuestPicker.resolve($0, input) } }
            } ?? DailyQuestPicker.pick(input)
            for pick in picks { insert(pick, periodKey: dayKey, day: day, at: date, expires: true) }
        }
        let weekKey = calendar.weekKey(for: date).rawValue
        if checkedPeriods.insert("week|\(weekKey)|\(dayKey)").inserted, instances(periodKey: weekKey).isEmpty {
            let input = weekly()
            let picks = forcing.map { forced in
                forced.weekly.compactMap { WeeklyQuestPicker.make($0.key, count: $0.count ?? 1, input) }
            } ?? WeeklyQuestPicker.pick(input)
            for pick in picks { insert(pick, periodKey: weekKey, day: day, at: date, expires: false) }
        }
    }

    /// Нова доба чи перемкнений пояс: перевірити видачу заново.
    func resetIssueChecks() {
        checkedPeriods.removeAll()
        periodCache.removeAll()
    }

    private func insert(_ pick: QuestPick, periodKey: String, day: DayKey, at date: Date, expires: Bool) {
        let expiresAt = expires ? pick.deadlineMinute.map { moment(day, minute: $0) } : nil
        let instance = QuestInstance(
            defKey: pick.key, periodKey: periodKey, target: 1, assignedAt: date, expiresAt: expiresAt,
            rewardXp: pick.rewardXp, difficultyRaw: pick.difficulty.rawValue, deadlineMinute: pick.deadlineMinute,
            blockIndex: pick.blockIndex, count: pick.count
        )
        store.insertQuest(instance)
        periodCache[periodKey, default: []].append(instance)
        store.save()
    }

    // MARK: - Оцінка

    /// Перераховує прогрес завдань дня й тижня. Повертає ті, що щойно закрилися, — на них нараховується XP.
    /// Порції рахуються за своїм часом, тож закрите «до T» лишається закритим, навіть якщо оцінка запізнилась;
    /// невиконані з дедлайном до `now` — прострочені, мовчки (§7). `now` — годинник, а не подія: подія може бути
    /// порцією з минулого (повернута, демо).
    @discardableResult
    func evaluate(at date: Date, now: Date, inputs: QuestInputs, triggerRef: UUID?) -> [QuestInstance] {
        var justCompleted: [QuestInstance] = []
        var changed = false
        for instance in instances(at: date) where instance.state == .active || instance.isDone {
            guard let definition = QuestCatalog.definition(instance.defKey) else { continue }
            let result = progress(instance, definition, at: date, inputs: inputs)
            changed = apply(result, to: instance) || changed
            if result.met, instance.state == .active {
                instance.state = .completed
                instance.completedAt = date
                instance.completedByRef = triggerRef
                justCompleted.append(instance)
                changed = true
            } else if instance.state == .active, let expiresAt = instance.expiresAt, expiresAt <= now {
                instance.state = .expired
                changed = true
            }
        }
        if changed { store.save() }
        return justCompleted
    }

    /// Пише прогрес лише коли він змінився: зайвий запис робить модель брудною, а `save()` — дорожчим.
    private func apply(_ result: QuestProgress, to instance: QuestInstance) -> Bool {
        guard instance.progress != result.progress || instance.target != result.target else { return false }
        instance.progress = result.progress
        instance.target = result.target
        return true
    }

    /// Відкат: завдання, умова якого більше не виконується, знову відкрите. Після дедлайну — одразу прострочене:
    /// відкрите знову після T не показується (§7).
    @discardableResult
    func revert(at date: Date, now: Date, inputs: QuestInputs, policy: RevertPolicy) -> [QuestInstance] {
        guard policy == .full else { return [] }
        var reopened: [QuestInstance] = []
        for instance in instances(at: date) where instance.isDone {
            guard let definition = QuestCatalog.definition(instance.defKey) else { continue }
            let result = progress(instance, definition, at: date, inputs: inputs)
            _ = apply(result, to: instance)
            if !result.met {
                let overdue = instance.expiresAt.map { $0 <= now } ?? false
                instance.state = overdue ? .expired : .active
                instance.completedAt = nil
                instance.completedByRef = nil
                reopened.append(instance)
            }
        }
        store.save()
        return reopened
    }

    private func instances(at date: Date) -> [QuestInstance] {
        instances(periodKey: calendar.dayKey(for: date).rawValue)
            + instances(periodKey: calendar.weekKey(for: date).rawValue)
    }

    private func instances(periodKey: String) -> [QuestInstance] {
        if let cached = periodCache[periodKey] { return cached }
        let fetched = store.quests(scope: nil, periodKey: periodKey)
        periodCache[periodKey] = fetched
        return fetched
    }

    private func progress(_ instance: QuestInstance, _ definition: QuestDefinition, at date: Date,
                          inputs: QuestInputs) -> QuestProgress {
        if case let .legacy(rule, target) = definition.condition {
            let value = rule.value(in: inputs.rules)
            let goal = target.resolve(dailyGoalMl: inputs.rules.dailyGoalMl)
            return QuestProgress(progress: value, target: goal, met: value >= goal)
        }
        let isWeekly = definition.scope == .weekly
        let params = QuestParams(
            deadlineMinute: isWeekly ? nil : instance.deadlineMinute,
            goalMedianMinute: isWeekly ? instance.deadlineMinute : nil,
            blockIndex: instance.blockIndex, count: instance.count, glassMl: inputs.glassMl, unit: inputs.unit
        )
        return definition.condition.evaluate(days: days(of: instance, isWeekly: isWeekly, at: date, inputs: inputs),
                                             params: params)
    }

    /// Дні періоду: щоденне — свій день, тижневе — від дня видачі до сьогодні в межах тижня (§5.7).
    private func days(of instance: QuestInstance, isWeekly: Bool, at date: Date, inputs: QuestInputs) -> [QuestDay] {
        guard isWeekly else { return [inputs.day(DayKey(rawValue: instance.periodKey))] }
        let from = calendar.dayKey(for: instance.assignedAt)
        let sunday = calendar.dayKey(offsetDays: 6, from: calendar.weekStart(of: from))
        let to = min(calendar.dayKey(for: date), sunday)
        guard from <= to else { return [] }
        return (from.ordinal...to.ordinal).map { inputs.day(DayKey(ordinal: $0)) }
    }

    // MARK: - Знімок

    func board(at date: Date, day: (DayKey) -> QuestDay) -> QuestBoard {
        let today = calendar.dayKey(for: date)
        let weekKey = calendar.weekKey(for: date).rawValue
        let daysLeft = 7 - today.weekdayIndex
        let blockCount = day(today).blocks.count
        let isVisible = { (instance: QuestInstance) in
            instance.isDone || (instance.state == .active && (instance.expiresAt.map { $0 > date } ?? true))
        }
        let visible = { (instances: [QuestInstance]) in
            instances.filter(isVisible)
                .compactMap { self.snapshot($0, blockCount: blockCount) }
                .sorted { Self.order($0.key) < Self.order($1.key) }
        }
        let daily = instances(periodKey: today.rawValue)
        let weekly = instances(periodKey: weekKey)
        return QuestBoard(
            daily: visible(daily),
            weekly: visible(weekly),
            weeklyStartsMonday: weekly.isEmpty && daysLeft < WeeklyQuestPicker.minDaysLeft,
            weekDaysLeft: daysLeft,
            // Скасоване (`cancelled`) — не прострочене: його людина не бачила.
            expiredDaily: daily.filter { !isVisible($0) && ($0.state == .expired || $0.state == .active) }.count
        )
    }

    private static let catalogOrder = Dictionary(QuestCatalog.all.enumerated().map { ($1.key, $0) },
                                                 uniquingKeysWith: { first, _ in first })

    /// «Темп» над «Ритмом», «Сталість» над «Звичкою» — порядок каталогу, не порядок вставки.
    private static func order(_ key: String) -> Int { catalogOrder[key] ?? .max }

    private func snapshot(_ instance: QuestInstance, blockCount: Int) -> QuestSnapshot? {
        guard let definition = QuestCatalog.definition(instance.defKey) else { return nil }
        return QuestSnapshot(
            id: instance.id, key: instance.defKey, scope: definition.scope, slot: definition.slot,
            title: definition.title, kind: definition.kind, progress: instance.progress, target: instance.target,
            isDone: instance.isDone, difficulty: QuestDifficulty(rawValue: instance.difficultyRaw),
            rewardXp: instance.rewardXp > 0 ? instance.rewardXp : definition.legacyXp,
            deadline: instance.expiresAt,
            deadlineMinute: definition.scope == .daily ? instance.deadlineMinute : nil,
            count: instance.count, blockIndex: instance.blockIndex,
            blockCount: instance.blockIndex == nil ? nil : blockCount
        )
    }

    private func moment(_ day: DayKey, minute: Int) -> Date {
        calendar.calendar.date(byAdding: .minute, value: minute, to: calendar.date(from: day)) ?? calendar.date(from: day)
    }
}
