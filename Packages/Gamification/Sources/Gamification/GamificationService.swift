import Foundation
import Core
import Persistence
import Metrics

/// Координатор гейміфікації: єдиний підписник шини метрик, який у детермінованому
/// порядку прокручує серії → завдання → досягнення → XP.
///
/// Модуль обліку води про нього не знає — звʼязок односторонній через `MetricsService`.
@MainActor
public final class GamificationService: MetricsSubscriber {
    let store: GamificationStoreProtocol
    private let dayLogs: DayLogRepositoryProtocol
    private let profiles: ProfileRepositoryProtocol
    private let metrics: MetricsService
    let calendar: CalendarService

    public let xp: XPEngine
    public let streaks: StreakEngine
    public let quests: QuestEngine
    public let achievements: AchievementEngine
    public var revertPolicy: RevertPolicy

    /// Захист від рекурсії: внутрішні події (XP, розблокування) не запускають новий цикл.
    private var isEvaluating = false

    /// Досягнення, відкриті діями користувача з моменту останнього `takeRecentUnlocks()`.
    /// Черга, а не повернене значення: `HydrationService` про гейміфікацію не знає,
    /// тож дізнатись «що відкрила ця порція» екран може лише тут.
    private var recentUnlocks: [String] = []
    /// Подарунок за повернення й «Знову в ритмі» з тієї самої дії — та сама черга (§12.5).
    private var pendingComebackGift: UUID?
    private var pendingBounceBackXp: Int?

    public init(
        store: GamificationStoreProtocol,
        dayLogs: DayLogRepositoryProtocol,
        profiles: ProfileRepositoryProtocol,
        metrics: MetricsService,
        calendar: CalendarService,
        curve: LevelCurve = LinearLevelCurve(),
        rules: XPRules = .default,
        revertPolicy: RevertPolicy = .full
    ) {
        self.store = store
        self.dayLogs = dayLogs
        self.profiles = profiles
        self.metrics = metrics
        self.calendar = calendar
        self.revertPolicy = revertPolicy
        self.xp = XPEngine(store: store, metrics: metrics, calendar: calendar, curve: curve, rules: rules)
        self.streaks = StreakEngine(store: store, dayLogs: dayLogs, calendar: calendar)
        self.quests = QuestEngine(store: store, calendar: calendar)
        self.achievements = AchievementEngine(store: store, metrics: metrics)
    }

    /// Підписка на шину + початкова синхронізація стану.
    public func bootstrap() {
        achievements.bootstrap()
        xp.recalculateFromJournal(at: calendar.now)
        metrics.subscribe(self)
        refresh(at: calendar.now)
    }

    /// Повний перерахунок стану — на старті застосунку та при зміні доби.
    public func refresh(at date: Date) {
        grantLevelRewards(at: date)
        recomputeStreaks(at: date)
        let context = makeContext(at: date)
        quests.ensureInstances(context: context, level: xp.progress().level)
        let completed = quests.evaluate(context: context, triggerRef: nil)
        awardQuestXP(completed, at: date)
        let unlocked = achievements.evaluate(context: makeContext(at: date), triggerRef: nil)
        awardAchievementXP(unlocked, at: date)
    }

    // MARK: - MetricsSubscriber

    public func metricsDidRecord(_ event: RecordedMetricEvent, service: MetricsService) {
        guard !Self.internalMetrics.contains(event.name), !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        let date = event.occurredAt

        if event.name == .dayGoalMet {
            recomputeStreaks(at: date)
            publishStreakMetric(at: date)
        }

        let streak = streaks.summary().current
        if event.name == .intakeAdded {
            xp.award(
                amount: xp.rules.perIntake, reason: .intake,
                refId: event.sourceRef, at: date, streak: streak
            )
            grantComebackGiftIfDue(event)
            awardDayPartGoalIfDue(event)
        }
        if event.name == .dayGoalMet {
            xp.award(amount: xp.rules.perDailyGoal, reason: .dailyGoal, refId: event.sourceRef, at: date)
            awardBounceBackIfDue(event)
        }

        let context = makeContext(at: date)
        quests.ensureInstances(context: context, level: xp.progress().level)
        let completed = quests.evaluate(context: context, triggerRef: event.sourceRef)
        awardQuestXP(completed, at: date)

        let unlocked = achievements.evaluate(context: makeContext(at: date), triggerRef: event.sourceRef)
        awardAchievementXP(unlocked, at: date)
        recentUnlocks.append(contentsOf: unlocked.map(\.key))

        grantLevelRewards(at: date)
    }

    /// Кожен новий рівень кладе свій приз в інвентар (SPEC-PRIZES §3.4).
    /// Дедуплікація — за детермінованим ключем, тому повторний виклик безпечний.
    /// Відкат рівня призу не забирає: повторна видача однаково неможлива, а витрачену
    /// заморозку не забереш — «виданий приз не відкликається» єдине несуперечливе правило.
    @discardableResult
    public func grantLevelRewards(at date: Date) -> [RewardItem] {
        let level = xp.progress().level
        guard level > 1 else { return [] }

        let existing = Set(store.rewardItems().compactMap(\.acquiredByRef))
        var granted: [RewardItem] = []

        for lvl in 2...level {
            for definition in RewardCatalog.rewards(forLevel: lvl) {
                let ref = DeterministicID.uuid(from: "level:\(lvl):\(definition.key)")
                guard !existing.contains(ref) else { continue }
                let item = RewardItem(
                    defKey: definition.key, source: .level, acquiredAt: date, acquiredByRef: ref
                )
                store.insertReward(item)
                granted.append(item)
            }
        }
        if !granted.isEmpty { store.save() }
        return granted
    }

    public func metricsDidRevert(_ events: [RecordedMetricEvent], sourceRef: UUID, service: MetricsService) {
        guard !isEvaluating else { return }
        isEvaluating = true
        defer { isEvaluating = false }

        let date = events.first?.occurredAt ?? calendar.now
        // 1. Забираємо XP, нарахований саме цією дією.
        xp.revert(refId: sourceRef, at: date)
        // 2. Серія перераховується з денних логів — вона вже врахувала зміну.
        recomputeStreaks(at: date)

        let context = makeContext(at: date)
        // 3. Завдання та досягнення знімаються, якщо умова більше не виконується.
        let reopened = quests.revert(context: context, sourceRef: sourceRef, policy: revertPolicy)
        for quest in reopened {
            xp.revert(refId: quest.id, at: date)
        }
        for key in achievements.revert(context: context, sourceRef: sourceRef, policy: revertPolicy, at: date) {
            xp.revert(refId: DeterministicID.uuid(from: "achievement:\(key)"), at: date)
            recentUnlocks.removeAll { $0 == key }
        }
        // 4. «Знову в ритмі» тримається на закритій нормі дня: норму відкотили — і бонус теж.
        //    Повернута порція знову запише `day.goalMet`, і бонус нарахується наново.
        for event in events where event.name == .dayGoalMet {
            if xp.revert(refId: Self.bounceBackRef(DayKey(rawValue: event.dayKey)), at: date) > 0 {
                pendingBounceBackXp = nil
            }
        }
        // 5. Ціль частини доби: порцію прибрали — блок міг опуститися нижче цілі.
        for event in events where event.name == .intakeAdded {
            revertDayPartGoalIfLost(event, at: date)
        }
    }

    // MARK: - Знімки для UI

    public func levelProgress() -> LevelProgress { xp.progress() }
    /// Серія + кількість готових заморозок з інвентаря (жетонів у `StreakState` більше немає).
    public func streakSummary() -> StreakSummary {
        let summary = streaks.summary()
        let freezes = store.rewardItems(defKey: RewardCatalog.freezeKey).filter { $0.state == .ready }.count
        return StreakSummary(
            current: summary.current, longest: summary.longest,
            freezeTokens: freezes, lastCountedDay: summary.lastCountedDay
        )
    }
    public func dailyQuests(at date: Date? = nil) -> [QuestSnapshot] {
        quests.snapshots(scope: .daily, at: date ?? calendar.now)
    }
    public func weeklyQuests(at date: Date? = nil) -> [QuestSnapshot] {
        quests.snapshots(scope: .weekly, at: date ?? calendar.now)
    }
    public func achievementSnapshots() -> [AchievementSnapshot] { achievements.snapshots() }
    public var hasUnseenAchievements: Bool { achievements.hasUnseenUnlocks }
    public func markAchievementsSeen() { achievements.markAllSeen(at: calendar.now) }
    public func markAchievementSeen(key: String) { achievements.markSeen(key: key, at: calendar.now) }

    /// Забирає все, що відкрилось з попереднього виклику, і очищає чергу.
    /// Екран викликає це до і після дії: «до» — щоб не показати тост за чуже розблокування
    /// (стартовий `refresh`, демо-історія, повернута порція).
    public func takeRecentUnlocks() -> RecentUnlocks {
        defer {
            recentUnlocks.removeAll()
            pendingComebackGift = nil
            pendingBounceBackXp = nil
        }
        var result = RecentUnlocks(bounceBackXp: pendingBounceBackXp)
        if !recentUnlocks.isEmpty {
            let snapshots = achievements.snapshots().filter(\.isUnlocked)
            result.achievements = recentUnlocks.compactMap { key in snapshots.first { $0.key == key } }
        }
        if let giftId = pendingComebackGift {
            result.comebackGift = prizes().first { $0.id == giftId }
        }
        return result
    }

    // MARK: - Для сповіщень (SPEC-NOTIFICATIONS)

    /// Серія на сьогодні, учора й позавчора — порятунок серії й «Знову в ритмі».
    public func streakFacts(at date: Date? = nil) -> StreakFacts {
        streaks.facts(at: date ?? calendar.now)
    }

    /// Коли востаннє дарували ⚡ за повернення — сповіщення 7-го дня згадує подарунок,
    /// лише якщо минуло 30 днів (§12.5, §14.2).
    public func lastComebackGiftAt() -> Date? {
        store.rewardItems().filter { $0.source == .comeback }.map(\.acquiredAt).max()
    }

    /// День останнього нарахованого (не відкоченого) «Знову в ритмі».
    public func lastBounceBackDay() -> DayKey? {
        store.xpEntries(reason: .bounceBack).first { $0.revertedAt == nil }.map { DayKey(rawValue: $0.dayKey) }
    }

    // MARK: - Призи (SPEC-PRIZES)

    /// Усі призи з відомими ключами, у т. ч. використані: екранам потрібен `prizeInventory()`,
    /// а повний список — тестам і аналітиці.
    public func prizes(at date: Date? = nil) -> [RewardSnapshot] {
        let now = date ?? calendar.now
        return store.rewardItems().compactMap { item in
            guard let definition = RewardCatalog.definition(item.defKey) else { return nil }
            return RewardSnapshot(
                id: item.id, key: item.defKey, title: definition.title, details: definition.details,
                emoji: definition.emoji, kind: definition.kind, state: Self.prizeState(item, at: now),
                isNew: item.state == .ready && item.seenAt == nil,
                acquiredAt: item.acquiredAt, activatedAt: item.activatedAt, expiresAt: item.expiresAt
            )
        }
    }

    /// Інвентар для блоку 3f і екрана «Призи»: діючі + готові стоси.
    public func prizeInventory(at date: Date? = nil) -> PrizeInventory {
        let now = date ?? calendar.now
        let snapshots = prizes(at: now)
        let hasFreeze = snapshots.contains { $0.key == RewardCatalog.freezeKey && $0.state == .ready }
        // `freezeTarget` читає DayLog — не рахуємо його, коли заморожувати нічим.
        return snapshots.inventory(freezeTarget: hasFreeze ? streaks.freezeTarget(at: now) : nil)
    }

    public func freezeTarget(at date: Date? = nil) -> FreezeTarget {
        streaks.freezeTarget(at: date ?? calendar.now)
    }

    /// Кінець дії буста, увімкненого в `date`: найближча локальна північ, а не +24 год —
    /// «день» у застосунку одиниця всього (норма, серія, завдання).
    public func boostExpiry(activatedAt date: Date) -> Date {
        calendar.date(from: calendar.dayKey(offsetDays: 1, from: calendar.dayKey(for: date)))
    }

    public var hasUnseenPrizes: Bool {
        store.rewardItems().contains { $0.state == .ready && $0.seenAt == nil && RewardCatalog.definition($0.defKey) != nil }
    }

    /// Гасить крапку «нове» на всіх готових — при відкритті екрана «Призи».
    public func markPrizesSeen() { markSeen { _ in true } }

    /// Гасить крапку «нове» на одному стосі — при відкритті його картки.
    public func markPrizesSeen(key: String) { markSeen { $0.defKey == key } }

    /// Кладе приз в інвентар поза рівнями (демо-дані; у майбутньому — призи за завдання).
    @discardableResult
    public func grantPrize(key: String, source: RewardSource, at date: Date? = nil) -> RewardSnapshot? {
        guard RewardCatalog.definition(key) != nil else { return nil }
        let item = RewardItem(defKey: key, source: source, acquiredAt: date ?? calendar.now)
        store.insertReward(item)
        store.save()
        return prizes(at: date).first { $0.id == item.id }
    }

    /// Використовує заморозку. День обирається **тут**, за `freezeTarget` на цю мить, а не
    /// той, що був на кнопці: якщо між відкриттям картки й тапом настала північ, ціль інша.
    /// `false` — приз не готовий або заморожувати нічого (сьогодні вже зараховано).
    @discardableResult
    public func useFreeze(prizeId: UUID, at date: Date? = nil) -> Bool {
        let now = date ?? calendar.now
        guard let item = readyItem(id: prizeId, key: RewardCatalog.freezeKey) else { return false }
        let today = calendar.dayKey(for: now)
        let day: DayKey
        switch streaks.freezeTarget(at: now) {
        case .yesterday: day = calendar.dayKey(offsetDays: -1, from: today)
        case .today: day = today
        case .todayAlreadyCounted: return false
        }

        item.state = .used
        item.activatedAt = now
        item.usedOnDayKey = day.rawValue
        store.save()
        streaks.freeze(day: day, at: now)
        // Заморожений учорашній день зарахований — ритм не обривався, і «Знову в ритмі»,
        // нарахований сьогодні раніше, вже не заслужений (SPEC-NOTIFICATIONS §12.5 Б).
        if day != today { xp.revert(refId: Self.bounceBackRef(today), at: now) }
        recordActivation(item, at: now)
        return true
    }

    /// Вмикає «Подвійний XP» до найближчої півночі. Одночасно діє лише один буст:
    /// черги немає, поки діє — `false`.
    @discardableResult
    public func activateBoost(prizeId: UUID, at date: Date? = nil) -> Bool {
        let now = date ?? calendar.now
        guard let item = readyItem(id: prizeId, key: RewardCatalog.boostKey),
              xp.boostMultiplier(at: now) == 1 else { return false }

        item.state = .active
        item.activatedAt = now
        item.expiresAt = boostExpiry(activatedAt: now)
        store.save()
        xp.invalidateBoosts()
        recordActivation(item, at: now)
        return true
    }

    /// Нагороди за рівні — список для шторки «Нагороди за рівні» (макет 3f).
    public func levelRewards(upTo level: Int = 12) -> [LevelRewardSnapshot] {
        let current = xp.progress().level
        return (1...max(level, current + 4)).flatMap { lvl in
            RewardCatalog.rewards(forLevel: lvl).map { definition in
                LevelRewardSnapshot(
                    level: lvl, key: definition.key, title: definition.title,
                    details: definition.details, emoji: definition.emoji, isUnlocked: lvl <= current
                )
            }
        }
    }

    public func nextLevelRewards() -> (level: Int, rewards: [LevelRewardSnapshot]) {
        let next = xp.progress().level + 1
        let rewards = RewardCatalog.rewards(forLevel: next).map {
            LevelRewardSnapshot(
                level: next, key: $0.key, title: $0.title,
                details: $0.details, emoji: $0.emoji, isUnlocked: false
            )
        }
        return (next, rewards)
    }

    // MARK: - Внутрішнє

    /// Події, на які гейміфікація не реагує. Сповіщення сюди обов'язково: «доставлено»
    /// пишеться на кожне перепланування, і без цього кожна позначка ганяла б квести й досягнення.
    private static let internalMetrics: Set<MetricKey> = [
        .xpEarned, .levelReached, .achievementUnlocked, .questCompleted, .streakCurrent, .prizeActivated,
        .reminderResponded, .notificationDelivered, .notificationOpened, .notificationSnoozed, .notificationPaused
    ]

    // MARK: - Нагороди за повернення (SPEC-NOTIFICATIONS §12.5)

    /// А. ⚡ «Подвійний XP» за першу порцію після перерви ≥ 3 днів, не частіше ніж раз на 30 днів.
    ///
    /// Нагорода за дію, а не за відкриття застосунку чи реакцію на сповіщення: хто повернувся
    /// сам або має вимкнені сповіщення, отримує так само. Undo порції подарунок **не** забирає —
    /// виданий приз не відкликається (SPEC-PRIZES §3.4), зловживання обмежує частота.
    ///
    /// Перевірка йде на кожну порцію, тож перший відсів — дешевий: лише перша порція дня.
    private func grantComebackGiftIfDue(_ event: RecordedMetricEvent) {
        let day = DayKey(rawValue: event.dayKey)
        guard dayLogs.existingDayLog(for: day)?.entriesCount == 1,
              let lastActive = dayLogs.lastActiveDayKey(before: day),
              calendar.daysBetween(lastActive, day) >= xp.rules.comebackMinGapDays else { return }

        let ref = DeterministicID.uuid(from: "comeback:\(day.rawValue)")
        let items = store.rewardItems()
        guard !items.contains(where: { $0.acquiredByRef == ref }) else { return }
        if let lastGift = items.filter({ $0.source == .comeback }).map(\.acquiredAt).max(),
           calendar.daysBetween(calendar.dayKey(for: lastGift), day) < xp.rules.comebackCooldownDays {
            return
        }

        let item = RewardItem(
            defKey: RewardCatalog.boostKey, source: .comeback, acquiredAt: event.occurredAt, acquiredByRef: ref
        )
        store.insertReward(item)
        pendingComebackGift = item.id
    }

    /// Б. «Знову в ритмі»: +25 XP за норму, закриту наступного дня після пропуску, що обірвав
    /// серію ≥ 3, не частіше ніж раз на 7 днів.
    ///
    /// Ref — день, а не порція: XP тримається на `day.goalMet` і відкочується разом із ним, навіть
    /// коли видалили не ту порцію, що закрила норму. Множник серії `XPEngine` дає лише порціям,
    /// тож тут діє тільки буст.
    private func awardBounceBackIfDue(_ event: RecordedMetricEvent) {
        let day = DayKey(rawValue: event.dayKey)
        let facts = streaks.facts(at: calendar.date(from: day))
        guard !facts.countedYesterday,
              facts.lengthEndingDayBefore >= xp.rules.bounceBackMinStreak else { return }

        let ref = Self.bounceBackRef(day)
        guard !store.xpEntries(refId: ref).contains(where: { $0.revertedAt == nil }) else { return }
        if let last = lastBounceBackDay(), calendar.daysBetween(last, day) < xp.rules.bounceBackCooldownDays {
            return
        }

        let gained = xp.award(amount: xp.rules.perBounceBack, reason: .bounceBack, refId: ref, at: event.occurredAt)
        if gained > 0 { pendingBounceBackXp = gained }
    }

    static func bounceBackRef(_ day: DayKey) -> UUID {
        DeterministicID.uuid(from: "bounceBack:\(day.rawValue)")
    }

    // MARK: - Ціль частини доби (SPEC-NOTIFICATIONS §9)

    /// +10 XP, коли порції в межах частини доби набрали її ціль за кривою темпу.
    ///
    /// Перевіряється лише блок, куди потрапила ця порція: решта від неї не змінилась. Ref —
    /// день і частина, а не порція: XP тримається на блоці, і відкочується, коли блок опустився
    /// нижче цілі, навіть якщо видалили не ту порцію, що його закрила. Повернута порція знову
    /// публікує `intake.added` — і XP нараховується наново. Зміна норми посеред дня вже
    /// нарахований XP не перераховує (рішення від 05.10.2026, §24).
    private func awardDayPartGoalIfDue(_ event: RecordedMetricEvent) {
        let day = DayKey(rawValue: event.dayKey)
        guard let (block, portions) = dayPartState(day: day, at: event.occurredAt) else { return }
        let ref = Self.dayPartGoalRef(day, block)
        guard block.isReached(by: portions),
              !store.xpEntries(refId: ref).contains(where: { $0.revertedAt == nil }) else { return }
        xp.award(amount: xp.rules.perDayPartGoal, reason: .dayPartGoal, refId: ref, at: event.occurredAt)
    }

    private func revertDayPartGoalIfLost(_ event: RecordedMetricEvent, at date: Date) {
        let day = DayKey(rawValue: event.dayKey)
        guard let (block, portions) = dayPartState(day: day, at: event.occurredAt),
              !block.isReached(by: portions) else { return }
        xp.revert(refId: Self.dayPartGoalRef(day, block), at: date)
    }

    /// Блок частини доби, куди потрапляє момент, і всі порції цього дня. Порція до підйому
    /// належить першому блоку, після відбою — останньому. `nil` — без денного логу.
    private func dayPartState(day: DayKey, at date: Date) -> (GoalBlock, [TimedPortion])? {
        guard let log = dayLogs.existingDayLog(for: day) else { return nil }
        // Розклад — із запису дня: зміна підйому пізніше не переносить уже оцінені межі (WAT-39).
        let schedule = profile.schedule(for: log, isWeekend: calendar.isWeekend(day))
        guard let block = schedule.curve(goalMl: log.goalMlSnapshot).goalBlock(containing: minuteOfDay(date)) else {
            return nil
        }
        let portions = (log.intakes ?? []).filter { !$0.isDeleted }.map {
            TimedPortion(minute: minuteOfDay($0.createdAt), ml: $0.amountMl)
        }
        return (block, portions)
    }

    /// Профіль — живий об'єкт SwiftData: зміни розкладу він бачить сам, а вибірка на кожну
    /// порцію коштувала б помітно на шляху, який міряє `PerformanceTests`.
    private lazy var profile: UserProfile = profiles.profile()

    private func minuteOfDay(_ date: Date) -> Int {
        let parts = calendar.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Ключ XP за ціль частини доби — день і частина, якою блок закінчується.
    public static func dayPartGoalRef(_ day: DayKey, _ block: GoalBlock) -> UUID {
        DeterministicID.uuid(from: "dayPartGoal:\(day.rawValue):\(block.deadlinePart.key)")
    }

    private static func prizeState(_ item: RewardItem, at date: Date) -> PrizeState {
        switch item.state {
        case .ready: return .ready
        case .used: return .used
        case .expired: return .expired
        case .active:
            guard let expiresAt = item.expiresAt else { return .active }
            return date < expiresAt ? .active : .expired
        }
    }

    private func readyItem(id: UUID, key: String) -> RewardItem? {
        store.rewardItems(defKey: key).first { $0.id == id && $0.state == .ready }
    }

    private func markSeen(where matches: (RewardItem) -> Bool) {
        let unseen = store.rewardItems().filter { $0.state == .ready && $0.seenAt == nil && matches($0) }
        guard !unseen.isEmpty else { return }
        for item in unseen { item.seenAt = calendar.now }
        store.save()
    }

    /// Дія з призом — окрема дія користувача, тож і `commit()` свій, один (CLAUDE.md, батчинг).
    private func recordActivation(_ item: RewardItem, at date: Date) {
        metrics.record(MetricEvent(
            name: .prizeActivated, value: 1, occurredAt: date, sourceRef: item.id,
            payload: ["key": item.defKey]
        ))
        metrics.commit()
    }

    /// Перерахунок серії + відкат метрики `prize.activated` для заморозок, які повернулися
    /// в інвентар: інакше повторне використання того самого предмета відсіклось би
    /// ідемпотентністю шини. Під `isEvaluating`, щоб власний відкат не запустив цикл реверсу.
    private func recomputeStreaks(at date: Date) {
        streaks.recompute(at: date)
        let returned = streaks.takeReturnedFreezes()
        guard !returned.isEmpty else { return }
        let wasEvaluating = isEvaluating
        isEvaluating = true
        defer { isEvaluating = wasEvaluating }
        for id in returned {
            metrics.revert(sourceRef: id, at: date)
        }
    }

    private func makeContext(at date: Date) -> RuleContext {
        let streak = streaks.summary()
        return RuleContext(
            metrics: metrics,
            calendar: calendar,
            date: date,
            dailyGoalMl: profiles.currentGoalMl(on: calendar.dayKey(for: date)),
            currentStreak: streak.current,
            longestStreak: streak.longest
        )
    }

    private func publishStreakMetric(at date: Date) {
        let value = streaks.summary().current
        guard value > 0 else { return }
        let day = calendar.dayKey(for: date).rawValue
        metrics.record(MetricEvent(
            name: .streakCurrent, value: Double(value), occurredAt: date,
            sourceRef: DeterministicID.uuid(from: "streak:\(day):\(value)")
        ))
    }

    private func awardQuestXP(_ quests: [QuestInstance], at date: Date) {
        for quest in quests {
            guard let definition = QuestCatalog.definition(quest.defKey) else { continue }
            xp.award(amount: definition.rewardXp, reason: .questCompleted, refId: quest.id, at: date)
            metrics.record(MetricEvent(
                name: .questCompleted, value: 1, occurredAt: date, sourceRef: quest.id,
                payload: ["key": quest.defKey]
            ))
        }
    }

    private func awardAchievementXP(_ definitions: [AchievementDefinition], at date: Date) {
        for definition in definitions {
            xp.award(
                amount: definition.rewardXp, reason: .achievementUnlocked,
                refId: DeterministicID.uuid(from: "achievement:\(definition.key)"), at: date
            )
        }
    }
}
