import Foundation
import Core
import Persistence
import Metrics

/// Досягнення для режиму розробника — повний каталог без маскування: таємні з назвою, пасхалки й зняті теж.
public struct DeveloperAchievement: Identifiable, Sendable, Equatable {
    public let key: String
    public let title: String
    public let emoji: String
    public let category: AchievementCategory
    public let isUnlocked: Bool
    public let isSecret: Bool
    public let isEgg: Bool
    public let isRetired: Bool
    public let rewardXp: Int
    public let value: Double
    public let target: Double

    public var id: String { key }
}

/// Інстанс завдання для режиму розробника — разом зі станом, бо дошка скасованих і прострочених не показує.
public struct DeveloperQuest: Identifiable, Sendable {
    public let snapshot: QuestSnapshot
    public let state: QuestState

    public var id: UUID { snapshot.id }
}

/// Режим розробника (WAT-68): дії повз правила гри, щоб перевірити екрани й вікна, не виконуючи умов і не чекаючи
/// днів. Кожна — окрема дія користувача зі своїм `metrics.commit()`, і далі гра йде звичайним шляхом: XP за відкрите
/// піднімає рівень, рівень видає приз, виконане завдання відкриває «Тижневу мету».
extension GamificationService {
    /// Ref відкритого й виконаного вручну. Таке трималось не на умові, тож відкат порції його не знімає
    /// (`AchievementEngine.revert`, `QuestEngine.revert`) — лише «Закрити» / «Скасувати» тут же. Лише для самої
    /// примусової дії: прохід після неї відкриває за умовою, і відкрите ним мусить відкочуватись, як завжди.
    public static let developerRef = DeterministicID.uuid(from: "developer")

    // MARK: - Досягнення

    public func developerAchievements() -> [DeveloperAchievement] {
        let progress = Dictionary(store.allAchievementProgress().map { ($0.defKey, $0) },
                                  uniquingKeysWith: { first, _ in first })
        return AchievementCatalog.all.map { definition in
            let row = progress[definition.key]
            return DeveloperAchievement(
                key: definition.key, title: definition.title, emoji: definition.emoji, category: definition.category,
                isUnlocked: row?.isUnlocked ?? false, isSecret: definition.isSecret, isEgg: definition.secrecy.isEgg,
                isRetired: definition.isRetired, rewardXp: definition.rewardXp, value: row?.value ?? 0,
                target: definition.target
            )
        }
    }

    /// Відкрити, як відкрив би прохід: подія `achievement.unlocked`, XP за складністю й черга вікна відкриття.
    @discardableResult
    public func developerUnlock(achievement key: String, at date: Date? = nil) -> Bool {
        guard let definition = AchievementCatalog.definition(key) else { return false }
        let now = date ?? calendar.now
        let progress = store.achievementProgress(defKey: key) ?? {
            let created = AchievementProgress(defKey: key, target: definition.target)
            store.insertAchievement(created)
            return created
        }()
        guard !progress.isUnlocked else { return false }
        progress.value = max(progress.value, definition.target)
        progress.unlockedAt = now
        progress.unlockedByRef = Self.developerRef
        metrics.record(MetricEvent(
            name: .achievementUnlocked, value: 1, occurredAt: now, sourceRef: AchievementEngine.ref(key),
            payload: ["key": key]
        ))
        awardAchievementXP([definition], at: now)
        recentUnlocks.append(key)
        // XP міг дати рівень, а рівень і число відкритих — «Струмок» і колекції. Ref прохода — не `developerRef`:
        // відкрите за умовою має й відкочуватись за нею.
        evaluateAchievements(at: now, triggerRef: AchievementEngine.ref(key), announce: true)
        grantLevelRewards(at: now)
        metrics.commit()
        return true
    }

    /// Закрити: зняти відкриття й XP. Прохід тут свідомо не йде — інакше виконана умова відкрила б його тієї ж миті.
    /// Відкриється знову з наступною подією, що його рахує, і вдруге отримає вікно: `celebratedAt` теж скинуто.
    @discardableResult
    public func developerRelock(achievement key: String, at date: Date? = nil) -> Bool {
        guard let progress = store.achievementProgress(defKey: key), progress.isUnlocked else { return false }
        let now = date ?? calendar.now
        progress.unlockedAt = nil
        progress.unlockedByRef = nil
        progress.seenAt = nil
        progress.celebratedAt = nil
        progress.value = 0
        recentUnlocks.removeAll { $0 == key }
        withoutCascade {
            xp.revert(refId: AchievementEngine.ref(key), at: now)
            metrics.revert(sourceRef: AchievementEngine.ref(key), at: now)
        }
        metrics.commit()
        return true
    }

    // MARK: - XP

    @discardableResult
    public func developerAwardXp(_ amount: Int, at date: Date? = nil) -> Int {
        let now = date ?? calendar.now
        let gained = xp.award(amount: amount, reason: .debug, refId: UUID(), at: now)
        evaluateAchievements(at: now, triggerRef: nil, announce: true)
        grantLevelRewards(at: now)
        metrics.commit()
        return gained
    }

    /// Рівно до порогу наступного рівня — з поправкою на буст і загальний множник, що діють на будь-який XP.
    public func developerLevelUp(at date: Date? = nil) {
        let now = date ?? calendar.now
        let multiplier = xp.boostMultiplier(at: now) * xp.rules.xpMultiplier
        developerAwardXp(Int((Double(xp.progress().xpLeft) / multiplier).rounded(.up)), at: now)
    }

    // MARK: - Призи й серія

    /// Діючий буст закінчується зараз — щоб перевірити прострочення без очікування півночі.
    @discardableResult
    public func developerStopBoost(at date: Date? = nil) -> Bool {
        let now = date ?? calendar.now
        let active = store.rewardItems().filter { item in
            RewardCatalog.boostKeys.contains(item.defKey) && item.state == .active
                && (item.expiresAt.map { $0 > now } ?? false)
        }
        guard !active.isEmpty else { return false }
        for item in active { item.expiresAt = now }
        store.save()
        xp.invalidateBoosts()
        boostDaysCache = nil
        return true
    }

    public func isFrozen(_ day: DayKey) -> Bool {
        store.streakState().frozenDayKeys.contains(day.rawValue)
    }

    /// Заморозка дня без призу: інвентар не чіпається, лише ланцюг серії.
    public func developerSetFrozen(_ frozen: Bool, day: DayKey, at date: Date? = nil) {
        let now = date ?? calendar.now
        if frozen {
            guard streaks.freeze(day: day, at: now) else { return }
        } else {
            let state = store.streakState()
            guard state.frozenDayKeys.contains(day.rawValue) else { return }
            state.frozenDayKeys.removeAll { $0 == day.rawValue }
            store.save()
            streaks.recompute(at: now)
        }
        history.invalidate(day: day.rawValue)
        publishStreakMetric(at: now)
        evaluateAchievements(at: now, triggerRef: nil, announce: true)
        metrics.commit()
    }

    // MARK: - Завдання

    public func developerQuests(at date: Date? = nil) -> [DeveloperQuest] {
        let now = date ?? calendar.now
        return quests.developerInstances(at: now).compactMap { instance in
            quests.developerSnapshot(instance) { [unowned self] in self.questDay($0) }
                .map { DeveloperQuest(snapshot: $0, state: instance.state) }
        }
    }

    /// Видати будь-яке завдання каталогу сьогодні — з параметрами, як у пікера (T, блок, N), але без відбору.
    /// Несподіване з'являється через `delayMinutes`: нуль — одразу, більше — щоб перевірити сповіщення `.challenge`.
    @discardableResult
    public func developerIssueQuest(key: String, delayMinutes: Int = 0, at date: Date? = nil) -> Bool {
        guard let definition = QuestCatalog.definition(key) else { return false }
        let now = date ?? calendar.now
        let day = calendar.dayKey(for: now)
        // Спершу звичайна видача дня: інакше перша порція побачила б непорожній період і пікери промовчали б.
        settleQuests(at: now)
        let pick: QuestPick?
        switch definition.scope {
        case .daily:
            pick = DailyQuestPicker.resolve(definition, dailyPickInput(day: day, at: now))
        case .weekly:
            let input = weeklyPickInput(day: day)
            pick = WeeklyQuestPicker.make(key, count: max(1, min(definition.baseCount ?? 3, input.daysLeft)), input)
        case .adhoc:
            guard let input = surprisePickInput(day: day, at: now) else { return false }
            pick = SurprisePicker.resolve(key, start: calendar.minuteOfDay(now) + max(0, delayMinutes), input)
        }
        guard let pick else { return false }
        quests.developerIssue(pick, scope: definition.scope, day: day, at: now)
        // Умова могла вже виконатись — закрити одразу, з XP, як закрила б наступна порція.
        settleQuests(at: now)
        metrics.commit()
        return true
    }

    @discardableResult
    public func developerComplete(quest id: UUID, at date: Date? = nil) -> Bool {
        let now = date ?? calendar.now
        guard let instance = quests.developerInstances(at: now).first(where: { $0.id == id }),
              instance.state == .active else { return false }
        instance.state = .completed
        instance.completedAt = now
        instance.completedByRef = Self.developerRef
        store.save()
        awardQuestXP([instance], at: now)
        recordAllDailyQuestsIfDone([instance], at: now)
        evaluateAchievements(at: now, triggerRef: instance.id, announce: true)
        grantLevelRewards(at: now)
        metrics.commit()
        return true
    }

    /// Скасувати: зникає з дошки, а виконане ще й забирає свій XP і події — як відкат. ⚡ несподіваного лишається:
    /// виданий приз не відкликається (SPEC-PRIZES §3.4).
    @discardableResult
    public func developerCancel(quest id: UUID, at date: Date? = nil) -> Bool {
        let now = date ?? calendar.now
        guard let instance = quests.developerInstances(at: now).first(where: { $0.id == id }),
              instance.state != .cancelled else { return false }
        let completedAt = instance.isDone ? instance.completedAt ?? now : nil
        instance.state = .cancelled
        instance.completedAt = nil
        instance.completedByRef = nil
        store.save()
        if let completedAt {
            withoutCascade {
                xp.revert(refId: instance.id, at: now)
                metrics.revert(sourceRef: instance.id, at: now)
                if instance.periodKey.count == 10 {
                    metrics.revert(sourceRef: Self.allDailyQuestsRef(DayKey(rawValue: instance.periodKey)), at: now)
                }
                // «Тижнева мета» й «Сотня завдань» трималися на цьому завданні — як у відкаті порції (SPEC-QUESTS §7).
                for key in achievements.revert(achievementInputs(at: now), policy: revertPolicy, since: completedAt, at: now) {
                    xp.revert(refId: AchievementEngine.ref(key), at: now)
                    recentUnlocks.removeAll { $0 == key }
                }
            }
        }
        metrics.commit()
        return true
    }

    // MARK: - Внутрішнє

    /// Видача й оцінка, як на подію: виконане — з XP і досягненнями.
    private func settleQuests(at date: Date) {
        let completed = runQuests(at: date, triggerRef: nil)
        guard !completed.isEmpty else { return }
        awardQuestXP(completed, at: date)
        recordAllDailyQuestsIfDone(completed, at: date)
        evaluateAchievements(at: date, triggerRef: nil, announce: true)
        grantLevelRewards(at: date)
    }

    /// Відкат тут точковий: без цього `metricsDidRevert` пройшов би весь ланцюг і відкотив би завдання й досягнення,
    /// що до цієї дії стосунку не мають.
    private func withoutCascade(_ work: () -> Void) {
        let wasEvaluating = isEvaluating
        isEvaluating = true
        defer { isEvaluating = wasEvaluating }
        work()
    }
}
