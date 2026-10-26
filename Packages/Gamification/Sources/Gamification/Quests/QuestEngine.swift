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
    /// Несподіване й хвилина його появи сьогодні. Без нього під форсуванням несподіваних немає зовсім.
    public var surprise: (key: String, minute: Int)?

    public init(daily: [String] = [], weekly: [(key: String, count: Int?)] = [],
                surprise: (key: String, minute: Int)? = nil) {
        self.daily = daily
        self.weekly = weekly
        self.surprise = surprise
    }

    /// `daily:daily.wakeGlass,daily.glasses;weekly:weekly.goalDays=5,weekly.wakeGlassDays=5;surprise:surprise.glassNow@13:30`.
    /// Невідомі ключі пропускаються; без жодного відомого — `nil`.
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
            case "surprise":
                let item = parts[1].split(separator: "@").map(String.init)
                let clock = item.count > 1 ? item[1].split(separator: ":").compactMap { Int($0) } : []
                guard let key = item.first, QuestCatalog.definition(key)?.scope == .adhoc, clock.count == 2 else { continue }
                forcing.surprise = (key, clock[0] * 60 + clock[1])
            default:
                continue
            }
        }
        guard !forcing.daily.isEmpty || !forcing.weekly.isEmpty || forcing.surprise != nil else { return nil }
        self = forcing
    }

    public static func == (lhs: QuestForcing, rhs: QuestForcing) -> Bool {
        lhs.daily == rhs.daily && lhs.weekly.map(\.key) == rhs.weekly.map(\.key)
            && lhs.weekly.map(\.count) == rhs.weekly.map(\.count)
            && lhs.surprise?.key == rhs.surprise?.key && lhs.surprise?.minute == rhs.surprise?.minute
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
    /// Несподівані від пікера. Під `--uitest-*` вимкнено: демо-історія старша за 8 днів, і картка перекрила б чужі
    /// сценарії (QUESTS-PLAN §3.8). Форсоване (`forcing.surprise`) видається й так.
    public var surprisesEnabled = true
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
    ///
    /// Несподіване планується тут же, разом зі щоденними, — і лише тоді (§6.1): так «перша дія дня» означає саме
    /// її, а не перший запуск після оновлення чи вбитого застосунку.
    ///
    /// - Parameter surprise: входи `SurprisePicker`; `nil` — не сьогодні (подія з минулого дня).
    func ensureInstances(day: DayKey, at date: Date, daily: () -> DailyPickInput, weekly: () -> WeeklyPickInput,
                         surprise: () -> SurprisePickInput? = { nil }) {
        let dayKey = day.rawValue
        if checkedPeriods.insert("stale|\(dayKey)").inserted { expireStale(before: day) }
        if checkedPeriods.insert("day|\(dayKey)").inserted, instances(periodKey: dayKey).isEmpty {
            let input = daily()
            let picks = forcing.map { forced in
                forced.daily.compactMap { QuestCatalog.definition($0).map { DailyQuestPicker.resolve($0, input) } }
            } ?? DailyQuestPicker.pick(input)
            for pick in picks { insert(pick, periodKey: dayKey, day: day, at: date, expires: true) }
            issueSurprise(day: day, at: date, daily: picks, input: surprise)
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

    /// Минулі періоди, що так і лишились активними, — прострочені (WAT-67). Невиконане без дедлайну чи без події
    /// після дедлайну інакше назавжди лишалось би `active`: на екрані його не видно, але сходинки адаптивних завдань
    /// й історія мусять бачити провал. Тижневі — лише завершені тижні.
    ///
    /// Один запит на день, а не по запиту на період: `PerformanceTests` міряють і цей шлях.
    private func expireStale(before day: DayKey) {
        let currentWeek = calendar.weekKey(for: calendar.date(from: day)).rawValue
        var changed = false
        for instance in store.quests(scope: nil, periodKey: nil) where instance.state == .active {
            // Лише минуле: подія з минулого дня (повернута порція) не прострочує того, що після неї.
            let isPast = Self.day(of: instance).map { $0 < day } ?? (instance.periodKey < currentWeek)
            guard isPast else { continue }
            instance.state = .expired
            changed = true
        }
        if changed { store.save() }
    }

    private func issueSurprise(day: DayKey, at date: Date, daily: [QuestPick], input: () -> SurprisePickInput?) {
        let periodKey = Self.surprisePeriodKey(day)
        guard instances(periodKey: periodKey).isEmpty, forcing?.surprise != nil || (forcing == nil && surprisesEnabled),
              var input = input() else { return }
        input.dailyKeys = daily.map(\.key)
        input.dailyBlockIndex = daily.first { $0.key == "daily.closeBlock" }?.blockIndex
        let pick = forcing?.surprise.map { forced in SurprisePicker.resolve(forced.key, start: forced.minute, input) }
            ?? SurprisePicker.pick(input)
        guard let pick else { return }
        insertSurprise(pick, day: day)
    }

    private func insertSurprise(_ pick: QuestPick, day: DayKey) {
        guard let start = pick.startMinute, let end = pick.deadlineMinute else { return }
        let periodKey = Self.surprisePeriodKey(day)
        let instance = QuestInstance(
            defKey: pick.key, periodKey: periodKey, target: 1, assignedAt: moment(day, minute: start),
            expiresAt: moment(day, minute: end), rewardXp: pick.rewardXp, difficultyRaw: pick.difficulty.rawValue,
            deadlineMinute: end, blockIndex: pick.blockIndex, weekdayIndex: pick.weekdayIndex
        )
        store.insertQuest(instance)
        periodCache[periodKey, default: []].append(instance)
        store.save()
    }

    /// «Несподівані завдання» вимкнули — сьогоднішнє, що ще не виконане, зникає (SPEC-QUESTS §9.5). Скасоване, а не
    /// прострочене: людина його не ігнорувала.
    func cancelSurprise(day: DayKey) {
        let active = instances(periodKey: Self.surprisePeriodKey(day)).filter { $0.state == .active }
        guard !active.isEmpty else { return }
        for instance in active { instance.state = .cancelled }
        store.save()
    }

    /// Несподіване — свій період на день: у списку щоденних воно зіпсувало б «усі щоденні виконано» й «не вчорашнє».
    public static func surprisePeriodKey(_ day: DayKey) -> String { "adhoc:\(day.rawValue)" }

    /// День інстансу: щоденне й несподіване — свій день; тижневе — понеділок свого тижня не зберігає, тож `nil`.
    static func day(of instance: QuestInstance) -> DayKey? {
        let key = instance.periodKey.hasPrefix("adhoc:") ? String(instance.periodKey.dropFirst(6)) : instance.periodKey
        return key.count == 10 ? DayKey(rawValue: key) : nil
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
            blockIndex: pick.blockIndex, count: pick.count, targetMl: pick.targetMl
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
            // Несподіване до появи не виконується — лише скасовується (§6.4). Прогрес пишеться й тоді: ціль і «ще
            // скільки» потрібні тексту сповіщення, що прийде в мить появи.
            if definition.scope == .adhoc, instance.state == .active, now < instance.assignedAt {
                if isCancelled(instance, inputs: inputs) {
                    instance.state = .cancelled
                    changed = true
                } else {
                    changed = apply(progress(instance, definition, at: date, inputs: inputs), to: instance) || changed
                }
                continue
            }
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

    /// Скасування до появи (§6.4) — не «проігноровано»: людина його не бачила. Норму закрито, або для Н1 і Н2 частина
    /// вже йде за темпом — випито в блоці не менше, ніж крива чекає до появи. Н2 з'являється на початку блоку, де
    /// крива чекає нуль, тож для нього — лише вже закритий блок.
    private func isCancelled(_ instance: QuestInstance, inputs: QuestInputs) -> Bool {
        guard let dayKey = Self.day(of: instance) else { return false }
        let day = inputs.day(dayKey)
        if day.goalMet { return true }
        guard instance.blockIndex != nil, let block = day.block(instance.blockIndex) else { return false }
        if block.isReached(by: day.portions) { return true }
        let start = calendar.minuteOfDay(instance.assignedAt)
        let expected = day.curve.target(fromMinute: Double(block.fromMinute), toMinute: Double(start))
        let drunk = block.drunkMl(of: day.portions.filter { $0.minute < start })
        return expected > 0 && Double(drunk) >= expected
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
        // Виконане з режиму розробника трималось не на умові — відкат порції його не знімає.
        for instance in instances(at: date)
        where instance.isDone && instance.completedByRef != GamificationService.developerRef {
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
        let day = calendar.dayKey(for: date)
        return instances(periodKey: day.rawValue) + instances(periodKey: calendar.weekKey(for: date).rawValue)
            + instances(periodKey: Self.surprisePeriodKey(day))
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
            startMinute: definition.scope == .adhoc ? calendar.minuteOfDay(instance.assignedAt) : nil,
            goalMedianMinute: isWeekly ? instance.deadlineMinute : nil,
            blockIndex: instance.blockIndex, count: instance.count, targetMl: instance.targetMl,
            glassMl: inputs.glassMl, unit: inputs.unit
        )
        return definition.condition.evaluate(days: days(of: instance, isWeekly: isWeekly, at: date, inputs: inputs),
                                             params: params)
    }

    /// Дні періоду: щоденне — свій день, тижневе — від дня видачі до сьогодні в межах тижня (§5.7).
    private func days(of instance: QuestInstance, isWeekly: Bool, at date: Date, inputs: QuestInputs) -> [QuestDay] {
        guard isWeekly else { return Self.day(of: instance).map { [inputs.day($0)] } ?? [] }
        let from = calendar.dayKey(for: instance.assignedAt)
        let sunday = calendar.dayKey(offsetDays: 6, from: calendar.weekStart(of: from))
        let to = min(calendar.dayKey(for: date), sunday)
        guard from <= to else { return [] }
        return (from.ordinal...to.ordinal).map { inputs.day(DayKey(ordinal: $0)) }
    }

    // MARK: - Режим розробника (WAT-68)

    /// Завдання повз пікери й поверх уже виданих за період. Несподіване — одне на день: чинне спершу скасовується.
    func developerIssue(_ pick: QuestPick, scope: QuestScope, day: DayKey, at date: Date) {
        switch scope {
        case .daily: insert(pick, periodKey: day.rawValue, day: day, at: date, expires: true)
        case .weekly: insert(pick, periodKey: calendar.weekKey(for: date).rawValue, day: day, at: date, expires: false)
        case .adhoc:
            cancelSurprise(day: day)
            insertSurprise(pick, day: day)
        }
    }

    /// Усі інстанси дня, його тижня й несподіване дня — і скасовані, і прострочені: дошка їх ховає.
    func developerInstances(at date: Date) -> [QuestInstance] { instances(at: date) }

    func developerSnapshot(_ instance: QuestInstance, day: (DayKey) -> QuestDay) -> QuestSnapshot? {
        snapshot(instance, blockCount: day(calendar.dayKey(for: instance.assignedAt)).blocks.count)
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
        // Несподіване — і ще не видиме: головний і віджет показують його рівно в хвилину появи без нової дії, а план
        // сповіщень ставить на неї `.challenge` (§6.4, §6.6). Видимість — `QuestSnapshot.isVisible(at:)`.
        let surprise = instances(periodKey: Self.surprisePeriodKey(today)).first(where: isVisible)
        return QuestBoard(
            daily: visible(daily),
            weekly: visible(weekly),
            weeklyStartsMonday: weekly.isEmpty && daysLeft < WeeklyQuestPicker.minDaysLeft,
            weekDaysLeft: daysLeft,
            // Скасоване (`cancelled`) — не прострочене: його людина не бачила.
            expiredDaily: daily.filter { !isVisible($0) && ($0.state == .expired || $0.state == .active) }.count,
            surprise: surprise.flatMap { snapshot($0, blockCount: blockCount) }
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
            deadlineMinute: definition.scope == .weekly ? nil : instance.deadlineMinute,
            count: instance.count, blockIndex: instance.blockIndex,
            blockCount: instance.blockIndex == nil ? nil : blockCount,
            visibleFrom: definition.scope == .adhoc ? instance.assignedAt : nil,
            weekdayIndex: instance.weekdayIndex, targetMl: instance.targetMl
        )
    }

    private func moment(_ day: DayKey, minute: Int) -> Date {
        calendar.calendar.date(byAdding: .minute, value: minute, to: calendar.date(from: day)) ?? calendar.date(from: day)
    }
}
