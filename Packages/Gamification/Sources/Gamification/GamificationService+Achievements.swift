import Foundation
import Core
import Persistence
import Metrics

/// Досягнення в координаторі (WAT-24, SPEC-ACHIEVEMENTS-CATALOG): входи правил, прохід і кеші.
extension GamificationService {
    /// Функції, від яких залежать досягнення: «Ритм дня» й сповіщення (дозвіл у системі + головний вимикач).
    public var achievementGates: AchievementGates {
        AchievementGates(
            dayRhythm: profile.dayRhythmEnabled,
            notifications: profile.notificationsEnabled && notificationsAuthorized()
        )
    }

    /// Прохід досягнень із нагородою. XP за досягнення може підняти рівень, а рівень — відкрити «Струмок»,
    /// тож прохід повторюється, поки рівень росте (не більше трьох разів).
    ///
    /// - Parameter announce: відкрите потрапляє в чергу тоста. Стартовий і нічний `refresh` — ні: досягнення
    ///   заднім числом з історії не заслуга жодної дії.
    @discardableResult
    func evaluateAchievements(at date: Date, triggerRef: UUID?, announce: Bool) -> [AchievementDefinition] {
        let wasEvaluating = isEvaluating
        isEvaluating = true
        defer { isEvaluating = wasEvaluating }

        var all: [AchievementDefinition] = []
        for _ in 0..<3 {
            let levelBefore = xp.progress().level
            let unlocked = achievements.evaluate(achievementInputs(at: date), triggerRef: triggerRef)
            awardAchievementXP(unlocked, at: date)
            all += unlocked
            guard !unlocked.isEmpty, xp.progress().level > levelBefore else { break }
        }
        // XP за досягнення міг дати рівень — приз рівня одразу, а не з наступною подією (видача ідемпотентна).
        if !all.isEmpty { grantLevelRewards(at: date) }
        if announce { recentUnlocks.append(contentsOf: all.map(\.key)) }
        return all
    }

    func achievementInputs(at date: Date) -> AchievementInputs {
        // «Сьогодні» — пізніше з годинника й події: повернута вчорашня порція не робить учора сьогоднішнім днем.
        let today = max(calendar.today, calendar.dayKey(for: date))
        history.prepare(today: today, frozenDays: store.streakState().frozenDayKeys, boostDays: boostDays())
        return AchievementInputs(
            rules: makeContext(at: date),
            history: history,
            level: xp.progress().level,
            game: gameFacts(),
            burst: { [unowned self] key, count, seconds in self.burst(key, count: count, withinSeconds: seconds) },
            gates: achievementGates
        )
    }

    /// Що змінила подія: день у історії (порція, норма, відкат) чи серію подій метрики.
    func noteAchievementInputs(changedBy events: [RecordedMetricEvent]) {
        for event in events {
            if Self.historyMetrics.contains(event.name) { history.invalidate(day: event.dayKey) }
            burstCache[event.name.rawValue] = nil
        }
    }

    func invalidateAchievementCaches() {
        boostDaysCache = nil
        gameFactsCache = nil
        burstCache.removeAll()
    }

    /// Події, після яких змінюється запис дня.
    private static let historyMetrics: Set<MetricKey> = [.intakeAdded, .intakeRemoved, .intakeRestored, .dayGoalMet]

    // MARK: - Входи

    private func boostDays() -> Set<String> {
        if let boostDaysCache { return boostDaysCache }
        let days = Set(store.rewardItems()
            .filter { RewardCatalog.boostKeys.contains($0.defKey) }
            .compactMap { $0.activatedAt.map { calendar.dayKey(for: $0).rawValue } })
        boostDaysCache = days
        return days
    }

    private func gameFacts() -> [GameFact: Double] {
        if let gameFactsCache { return gameFactsCache }
        var mysteries = 0
        var choices = 0
        var triple = false
        for (level, grants) in levelClaims() {
            switch LevelRoadCatalog.node(forLevel: level) {
            case .mystery?:
                mysteries += 1
                if grants.contains(where: { $0.key == RewardCatalog.tripleKey }) { triple = true }
            case .choice?:
                choices += 1
            default:
                break
            }
        }
        let facts: [GameFact: Double] = [
            .mysteriesOpened: Double(mysteries), .levelChoices: Double(choices), .tripleFromMystery: triple ? 1 : 0
        ]
        gameFactsCache = facts
        return facts
    }

    /// Найбільше подій метрики в межах вікна: 1 — є `count` подій за `withinSeconds`, 0 — ні.
    private func burst(_ key: MetricKey, count: Int, withinSeconds seconds: Int) -> Double {
        if let cached = burstCache[key.rawValue] { return cached }
        let moments = metrics.events(key).map(\.occurredAt).sorted()
        var found = false
        if count > 0, moments.count >= count {
            for start in 0...(moments.count - count)
            where moments[start + count - 1].timeIntervalSince(moments[start]) <= Double(seconds) {
                found = true
                break
            }
        }
        let value: Double = found ? 1 : 0
        burstCache[key.rawValue] = value
        return value
    }

    // MARK: - «Усе на сьогодні»

    /// Подія «виконано всі щоденні завдання» — коли в цьому проході закрилось щоденне й відкритих не лишилось.
    /// Ref від дня: повторний виклик нічого не подвоює, а відкат завдання відкочує й подію.
    func recordAllDailyQuestsIfDone(_ completed: [QuestInstance], at date: Date) {
        guard let periodKey = completed.first(where: { $0.periodKey.count == 10 })?.periodKey else { return }
        let daily = store.quests(scope: .daily, periodKey: periodKey)
        guard !daily.isEmpty, daily.allSatisfy(\.isDone) else { return }
        metrics.record(MetricEvent(
            name: .questsAllDaily, value: 1, occurredAt: date,
            sourceRef: Self.allDailyQuestsRef(DayKey(rawValue: periodKey))
        ))
    }

    static func allDailyQuestsRef(_ day: DayKey) -> UUID {
        DeterministicID.uuid(from: "quest.allDaily:\(day.rawValue)")
    }
}
