import Foundation
import Core
import Persistence
import Metrics

// MARK: - Завдання

/// Ціль завдання: фіксована або привʼязана до денної норми.
public enum QuestTarget: Sendable {
    case fixed(Double)
    case dailyGoal
    case dailyGoalFraction(Double)

    @MainActor
    public func resolve(dailyGoalMl: Int) -> Double {
        switch self {
        case .fixed(let value): return value
        case .dailyGoal: return Double(dailyGoalMl)
        case .dailyGoalFraction(let f): return Double(dailyGoalMl) * f
        }
    }
}

public struct QuestDefinition: Sendable, Identifiable {
    public let key: String
    public let scope: QuestScope
    public let title: String
    public let rule: MetricRule
    public let target: QuestTarget
    public let rewardXp: Int
    public let minLevel: Int

    public var id: String { key }

    /// Завдання на частину доби («Випити воду зранку»): у режимі «просто норма» не видається (WAT-42, §28).
    public var isDayPartQuest: Bool {
        guard case .metric(let key, _, _) = rule.source else { return false }
        return MetricKey.dayParts.contains(key)
    }

    public init(
        key: String,
        scope: QuestScope,
        title: String,
        rule: MetricRule,
        target: QuestTarget,
        rewardXp: Int,
        minLevel: Int = 1
    ) {
        self.key = key
        self.scope = scope
        self.title = title
        self.rule = rule
        self.target = target
        self.rewardXp = rewardXp
        self.minLevel = minLevel
    }
}

public enum QuestCatalog {
    /// Щоденні (макет 1a і 3f: «Випити 2 л води», «Додати 4 записи»).
    public static let daily: [QuestDefinition] = [
        QuestDefinition(
            key: "daily.goal",
            scope: .daily,
            title: "Випити денну норму",
            rule: MetricRule(key: .intakeAdded, period: .day, aggregate: .sum),
            target: .dailyGoal,
            rewardXp: 25
        ),
        QuestDefinition(
            key: "daily.entries4",
            scope: .daily,
            title: "Додати 4 записи",
            rule: MetricRule(key: .intakeCount, period: .day, aggregate: .sum),
            target: .fixed(4),
            rewardXp: 25
        ),
        QuestDefinition(
            key: "daily.morning",
            scope: .daily,
            title: "Випити воду зранку",
            rule: MetricRule(key: .partMorning, period: .day, aggregate: .sum),
            target: .fixed(200),
            rewardXp: 25
        )
    ]

    /// Тижневі (макет 3f: «Стрік 7 днів поспіль», «Випити норму 5 днів»).
    public static let weekly: [QuestDefinition] = [
        QuestDefinition(
            key: "weekly.streak7",
            scope: .weekly,
            title: "Стрік 7 днів поспіль",
            rule: .currentStreak,
            target: .fixed(7),
            rewardXp: 100
        ),
        QuestDefinition(
            key: "weekly.goal5days",
            scope: .weekly,
            title: "Випити норму 5 днів",
            rule: MetricRule(key: .dayGoalMet, period: .week, aggregate: .sum),
            target: .fixed(5),
            rewardXp: 100
        )
    ]

    public static let all: [QuestDefinition] = daily + weekly

    public static func definition(_ key: String) -> QuestDefinition? {
        all.first { $0.key == key }
    }

    /// Скільки щоденних завдань показуємо одночасно (макети показують два).
    public static let dailySlots = 2
}

// MARK: - Досягнення

/// Каталог досягнень — `SPEC-ACHIEVEMENTS-CATALOG.md` (WAT-49, рішення від 15.10.2026), реалізація — WAT-24.
///
/// Ключі наявних семи (`first.drop`, `day.goal`, `big.gulp`, `streak.3/7/30`, `marathon`) не змінюються,
/// навіть коли змінилась назва чи опис: за ключем зберігається прогрес. XP — від складності
/// (`AchievementDifficulty.rewardXp`), остаточні числа — WAT-25. «Бульк!» 🫧 — пізніше (§8).
public enum AchievementCatalog {
    /// §4.1 💧 Вода — 14. Об'єм лише зарахований (стеля 120 %): перепивання драбину не пришвидшує.
    static let water: [AchievementDefinition] = [
        .init(key: "first.drop", title: "Перша крапля", details: "Перший запис води", emoji: "💧",
              category: .water, difficulty: .easy, rule: .metric(MetricRule(key: .intakeCount)), target: 1),
        .init(key: "day.goal", title: "Ціль дня", details: "Випито денну норму", emoji: "🎯",
              category: .water, difficulty: .easy, rule: .history(.goalDays), target: 1),
        // Літр залпом пити не варто, а записати одним записом пляшку, що розтяглась на годину, — нормально.
        .init(key: "big.gulp", title: "Великий ковток", details: "Літрова пляшка одним записом", emoji: "🥤",
              category: .water, difficulty: .easy, rule: .max(.intakeAdded), target: 1000),
        .init(key: "volume.1l", title: "Глечик", details: "1 л води загалом", emoji: "🏺",
              category: .water, difficulty: .easy, rule: .history(.countedMl), target: 1000),
        .init(key: "volume.10l", title: "Відро", details: "10 л води загалом", emoji: "🪣",
              category: .water, difficulty: .easy, rule: .history(.countedMl), target: 10_000),
        .init(key: "volume.50l", title: "Акваріум", details: "50 л води загалом", emoji: "🐠",
              category: .water, difficulty: .medium, rule: .history(.countedMl), target: 50_000),
        .init(key: "volume.100l", title: "Бочка", details: "100 л води загалом", emoji: "🛢️",
              category: .water, difficulty: .medium, rule: .history(.countedMl), target: 100_000),
        .init(key: "volume.250l", title: "Ванна", details: "250 л води загалом", emoji: "🛁",
              category: .water, difficulty: .hard, rule: .history(.countedMl), target: 250_000),
        .init(key: "volume.500l", title: "Басейн", details: "500 л води загалом", emoji: "🏊",
              category: .water, difficulty: .hard, rule: .history(.countedMl), target: 500_000),
        .init(key: "volume.1000l", title: "Тонна води", details: "1000 л води загалом", emoji: "🐳",
              category: .water, difficulty: .legendary, rule: .history(.countedMl), target: 1_000_000),
        .init(key: "portions.10", title: "Розминка", details: "10 порцій", emoji: "🔟",
              category: .water, difficulty: .easy, rule: .metric(MetricRule(key: .intakeCount)), target: 10),
        .init(key: "portions.100", title: "Сотня порцій", details: "100 порцій", emoji: "💯",
              category: .water, difficulty: .medium, rule: .metric(MetricRule(key: .intakeCount)), target: 100),
        .init(key: "portions.1000", title: "Тисяча порцій", details: "1000 порцій", emoji: "🎖️",
              category: .water, difficulty: .hard, rule: .metric(MetricRule(key: .intakeCount)), target: 1000),
        .init(key: "portions.5000", title: "П'ять тисяч", details: "5000 порцій", emoji: "👑",
              category: .water, difficulty: .legendary, rule: .metric(MetricRule(key: .intakeCount)), target: 5000)
    ]

    /// §4.2 🔥 Серії — 8 серій і 5 повернень. Серія — `longestStreak`: заморожений день тримає ланцюг,
    /// але не додає до числа.
    static let streaks: [AchievementDefinition] = [
        .init(key: "streak.3", title: "3 дні поспіль", details: "3 дні поспіль із нормою", emoji: "🔥",
              category: .streak, difficulty: .easy, rule: .metric(.longestStreak), target: 3),
        .init(key: "streak.7", title: "Тиждень поспіль", details: "7 днів поспіль із нормою", emoji: "⭐",
              category: .streak, difficulty: .easy, rule: .metric(.longestStreak), target: 7),
        .init(key: "streak.14", title: "Два тижні", details: "14 днів поспіль із нормою", emoji: "☄️",
              category: .streak, difficulty: .medium, rule: .metric(.longestStreak), target: 14),
        .init(key: "streak.30", title: "Місяць витримки", details: "30 днів поспіль із нормою", emoji: "🏆",
              category: .streak, difficulty: .medium, rule: .metric(.longestStreak), target: 30),
        .init(key: "streak.60", title: "Два місяці", details: "60 днів поспіль", emoji: "🚀",
              category: .streak, difficulty: .hard, rule: .metric(.longestStreak), target: 60),
        .init(key: "streak.100", title: "Сотня поспіль", details: "100 днів поспіль", emoji: "💎",
              category: .streak, difficulty: .hard, rule: .metric(.longestStreak), target: 100),
        .init(key: "streak.180", title: "Пів року", details: "180 днів поспіль", emoji: "🗻",
              category: .streak, difficulty: .hard, rule: .metric(.longestStreak), target: 180),
        .init(key: "streak.365", title: "Рік без пропусків", details: "365 днів поспіль", emoji: "🌞",
              category: .streak, difficulty: .legendary, rule: .metric(.longestStreak), target: 365),
        // Те саме правило, що дає XP «Знову в ритмі» (SPEC-NOTIFICATIONS §12.5 Б), лише без частоти.
        .init(key: "comeback.bounce", title: "Знову в ритмі", details: "Норма наступного дня після обриву серії",
              emoji: "🌱", category: .streak, difficulty: .easy,
              rule: .history(.bounceBacks(minStreak: XPRules.default.bounceBackMinStreak)), target: 1),
        .init(key: "comeback.wave", title: "Друга хвиля", details: "Нова серія 7 днів після обриву серії 7+",
              emoji: "🌊", category: .streak, difficulty: .medium, rule: .history(.secondWave(minStreak: 7)), target: 7),
        .init(key: "comeback.again", title: "Знову тут", details: "3 дні поспіль із нормою після перерви 7+ днів",
              emoji: "🌤️", category: .streak, difficulty: .medium, rule: .history(.backAfterBreak(breakDays: 7)), target: 3),
        .init(key: "comeback.rescue", title: "Вчасно", details: "Норма закрита після вечірнього «порятунку серії»",
              emoji: "🛟", category: .streak, difficulty: .easy, rule: .count(.streakRescued), target: 1,
              gate: .notifications),
        // «Повернення» — та сама подія, що й «Знову в ритмі», утретє.
        .init(key: "comeback.third", title: "Вода камінь точить", details: "Третє повернення після обриву серії",
              emoji: "🪨", category: .streak, difficulty: .medium,
              rule: .history(.bounceBacks(minStreak: XPRules.default.bounceBackMinStreak)), target: 3,
              secrecy: .hint("Терпіння й праця все перетруть"))
    ]

    /// §4.3 📅 Регулярність — 10. Пропуск рахунку не обнуляє: перші п'ять — дні не поспіль, решта — «поспіль»
    /// з м'якшою умовою, ніж у серії.
    static let regularity: [AchievementDefinition] = [
        .init(key: "goal.days5", title: "Перша п'ятірка", details: "5 днів із нормою", emoji: "🖐️",
              category: .regularity, difficulty: .easy, rule: .history(.goalDays), target: 5),
        .init(key: "marathon", title: "Марафон", details: "20 днів із нормою", emoji: "📅",
              category: .regularity, difficulty: .medium, rule: .history(.goalDays), target: 20),
        .init(key: "goal.days66", title: "Звичка",
              details: "66 днів із нормою — стільки в середньому формується звичка", emoji: "🧠",
              category: .regularity, difficulty: .hard, rule: .history(.goalDays), target: 66),
        .init(key: "goal.days100", title: "Сотня днів", details: "100 днів із нормою", emoji: "🏵️",
              category: .regularity, difficulty: .hard, rule: .history(.goalDays), target: 100),
        .init(key: "goal.days365", title: "Річні кільця", details: "365 днів із нормою", emoji: "🌳",
              category: .regularity, difficulty: .legendary, rule: .history(.goalDays), target: 365),
        // Тижневе завдання «Випити норму 5 днів» чотири рази поспіль.
        .init(key: "weeks.stable4", title: "Стабільний місяць", details: "4 тижні поспіль, у кожному 5+ днів із нормою",
              emoji: "📈", category: .regularity, difficulty: .medium,
              rule: .history(.stableWeeksRun(minGoalDays: 5)), target: 4),
        .init(key: "weeks.stable13", title: "Стабільний квартал",
              details: "13 тижнів поспіль, у кожному 5+ днів із нормою", emoji: "🧱",
              category: .regularity, difficulty: .hard, rule: .history(.stableWeeksRun(minGoalDays: 5)), target: 13),
        .init(key: "days.noZero", title: "Без нулів", details: "30 днів поспіль хоч з однією порцією", emoji: "✏️",
              category: .regularity, difficulty: .medium, rule: .history(.activeDaysRun), target: 30),
        .init(key: "days.neverTwice", title: "Ніколи двічі", details: "30 днів без двох пропусків поспіль", emoji: "🧷",
              category: .regularity, difficulty: .medium, rule: .history(.neverTwiceRun), target: 30),
        .init(key: "days.noDips", title: "Без провалів", details: "28 днів поспіль, кожен — від 80 % норми", emoji: "📉",
              category: .regularity, difficulty: .medium, rule: .history(.noDipsRun(percent: 80)), target: 28)
    ]

    /// §4.4 🌅 Ритм дня — 10. Цілі — блоки `GoalBlock`, ті самі, що в капсулі, XP і «Рівномірності»;
    /// підйом і відбій — зі знімка дня.
    static let dayRhythm: [AchievementDefinition] = [
        .init(key: "rhythm.morning", title: "Добрий ранок", details: "Закрито ціль ранку", emoji: "🌅",
              category: .dayRhythm, difficulty: .easy, rule: .history(.morningGoalDays), target: 1, gate: .dayRhythm),
        .init(key: "rhythm.allThree", title: "Ранок, день і вечір", details: "За день закрито всі три цілі", emoji: "🌈",
              category: .dayRhythm, difficulty: .easy, rule: .history(.allBlocksDays), target: 1, gate: .dayRhythm),
        .init(key: "rhythm.week", title: "Тиждень у ритмі", details: "7 днів, коли закрито всі три цілі", emoji: "🎼",
              category: .dayRhythm, difficulty: .medium, rule: .history(.allBlocksDays), target: 7, gate: .dayRhythm),
        .init(key: "rhythm.month", title: "Місяць у ритмі", details: "30 днів, коли закрито всі три цілі", emoji: "🎻",
              category: .dayRhythm, difficulty: .hard, rule: .history(.allBlocksDays), target: 30, gate: .dayRhythm),
        .init(key: "rhythm.wakeGlass", title: "Ранкова склянка",
              details: "10 днів: перша порція — за пів години після підйому", emoji: "🌄",
              category: .dayRhythm, difficulty: .medium, rule: .history(.wakeGlassDays(withinMinutes: 30)), target: 10),
        // Вікно спаду перед сном (WAT-43): менше нічних пробуджень.
        .init(key: "rhythm.quietEvening", title: "Тихий вечір", details: "10 днів: норма закрита за 2 год до відбою",
              emoji: "🌙", category: .dayRhythm, difficulty: .medium,
              rule: .history(.quietEveningDays(minutesBeforeSleep: 120)), target: 10),
        // «Рівномірність за день» рахується й без «Ритму дня», тож від перемикача не залежить.
        .init(key: "rhythm.even90", title: "Рівна крива", details: "«Рівномірність за день» — 90 зі 100", emoji: "〰️",
              category: .dayRhythm, difficulty: .medium, rule: .history(.bestEvenness), target: 90),
        .init(key: "rhythm.even97", title: "Ідеальна крива", details: "«Рівномірність за день» — 97 зі 100", emoji: "📐",
              category: .dayRhythm, difficulty: .hard, rule: .history(.bestEvenness), target: 97),
        .init(key: "rhythm.responsive", title: "Чуйність", details: "10 порцій за 15 хв після нагадування", emoji: "⏰",
              category: .dayRhythm, difficulty: .medium, rule: .count(.reminderQuick), target: 10, gate: .notifications),
        // Нагадування «відстаєш» не прийшло, бо весь день попереду кривої. Рахуються лише дні з увімкненими
        // нагадуваннями — інакше досягнення дісталося б задарма (подію пише `NotificationService`).
        .init(key: "rhythm.ahead", title: "На крок попереду", details: "7 днів із нормою без жодного нагадування",
              emoji: "🏃", category: .dayRhythm, difficulty: .medium, rule: .count(.dayGoalAhead), target: 7,
              gate: .notifications)
    ]

    /// §4.5 📊 Статистика й рекорди — 6.
    static let stats: [AchievementDefinition] = [
        .init(key: "record.streak", title: "Перевершити себе", details: "Серія довша за попередній рекорд (від 7 днів)",
              emoji: "🆙", category: .stats, difficulty: .medium, rule: .history(.recordBeaten(minStreak: 7)), target: 1),
        // Тоді ж «Типова доба» перестає казати «замало даних» — привід уперше на неї подивитись.
        .init(key: "stats.portrait", title: "Портрет дня",
              details: "14 днів обліку — «Типова доба» вже показує твій ритм", emoji: "🧬",
              category: .stats, difficulty: .medium, rule: .history(.activeDays), target: 14),
        // Єдине досягнення, що прямо заохочує не перебирати.
        .init(key: "stats.accuracy", title: "Влучність", details: "5 днів, коли випито 100–105 % норми", emoji: "🏹",
              category: .stats, difficulty: .medium, rule: .history(.accurateDays(fromPercent: 100, toPercent: 105)),
              target: 5),
        .init(key: "stats.bullseye", title: "В яблучко", details: "Рівно норма, до мілілітра", emoji: "🍎",
              category: .stats, difficulty: .easy, rule: .history(.exactGoalDays), target: 1,
              secrecy: .hint("Ні краплі зайвої")),
        .init(key: "stats.greenMonth", title: "Зелений місяць", details: "20+ днів із нормою за календарний місяць",
              emoji: "🟩", category: .stats, difficulty: .medium, rule: .history(.bestMonthGoalDays), target: 20),
        // Заморозка тут не допомагає — потрібна саме норма.
        .init(key: "stats.perfectMonth", title: "Ідеальний місяць", details: "Норма кожен день календарного місяця",
              emoji: "🗓️", category: .stats, difficulty: .hard, rule: .history(.perfectMonths), target: 1)
    ]

    /// §4.6 ⭐ Гра — 17. Рівні — лише віхи; емодзі призів (🧊 ⚡ 🌟 🎁) свідомо не беремо — досягнення читалось би
    /// як предмет. «Усе зібрано» — окремо, у `all`: його ціль рахується з каталогу.
    static let game: [AchievementDefinition] = [
        .init(key: "level.5", title: "Струмок", details: "Рівень 5", emoji: "💦",
              category: .game, difficulty: .easy, rule: .level, target: 5),
        .init(key: "level.10", title: "Річка", details: "Рівень 10", emoji: "🏞️",
              category: .game, difficulty: .medium, rule: .level, target: 10),
        .init(key: "level.20", title: "Море", details: "Рівень 20", emoji: "⛵",
              category: .game, difficulty: .medium, rule: .level, target: 20),
        .init(key: "level.30", title: "Океан", details: "Рівень 30", emoji: "🐋",
              category: .game, difficulty: .hard, rule: .level, target: 30),
        .init(key: "level.50", title: "Блакитна планета", details: "Рівень 50", emoji: "🌍",
              category: .game, difficulty: .legendary, rule: .level, target: 50),
        .init(key: "quest.first", title: "Перше завдання", details: "Виконано перше завдання", emoji: "📋",
              category: .game, difficulty: .easy, rule: .count(.questCompleted), target: 1),
        .init(key: "quest.allDaily", title: "Усе на сьогодні", details: "Виконано всі щоденні завдання за день",
              emoji: "✅", category: .game, difficulty: .easy, rule: .count(.questsAllDaily), target: 1),
        .init(key: "quest.100", title: "Сотня завдань", details: "Виконано 100 завдань", emoji: "🗂️",
              category: .game, difficulty: .medium, rule: .count(.questCompleted), target: 100),
        .init(key: "boost.goal", title: "Подвійна гра", details: "Активний буст і закрита норма того ж дня",
              emoji: "🎲", category: .game, difficulty: .easy, rule: .history(.boostGoalDays), target: 1),
        .init(key: "mystery.first", title: "Перша скриня", details: "Відкрито перший таємний приз", emoji: "🔓",
              category: .game, difficulty: .easy, rule: .game(.mysteriesOpened), target: 1),
        .init(key: "freeze.saved", title: "Порятунок", details: "Заморозка зберегла серію 7+ днів", emoji: "🛡️",
              category: .game, difficulty: .medium, rule: .history(.freezeSaves(minStreak: 7)), target: 1),
        .init(key: "mystery.5", title: "Пошук скарбів", details: "Відкрито 5 таємних призів", emoji: "🗝️",
              category: .game, difficulty: .hard, rule: .game(.mysteriesOpened), target: 5),
        .init(key: "mystery.triple", title: "Щаслива зірка", details: "З таємного призу випав «Потрійний XP»",
              emoji: "🍀", category: .game, difficulty: .medium, rule: .game(.tripleFromMystery), target: 1,
              secrecy: .hint("Іноді скриня щедріша")),
        .init(key: "collection.10", title: "Колекція", details: "10 досягнень", emoji: "🗃️",
              category: .game, difficulty: .easy, rule: .collection(.all), target: 10),
        .init(key: "collection.25", title: "Вітрина", details: "25 досягнень", emoji: "🖼️",
              category: .game, difficulty: .medium, rule: .collection(.all), target: 25),
        .init(key: "collection.50", title: "Музей", details: "50 досягнень", emoji: "🏛️",
              category: .game, difficulty: .hard, rule: .collection(.all), target: 50)
    ]

    /// §4.7 🧭 Відкриття — 15. Разові, з малим XP, кожне вчить однієї функції. Заднім числом не відновлюються:
    /// дій раніше не записували — окрім джерел порцій, вибору на шляху рівнів і прийнятого графіка.
    static let discovery: [AchievementDefinition] = [
        .init(key: "discover.custom", title: "Своя мірка", details: "Порція власного обʼєму через «Інше»", emoji: "✍️",
              category: .discovery, difficulty: .easy, rule: .count(.customPortion), target: 1),
        .init(key: "discover.undo", title: "Друга думка", details: "Порцію скасовано", emoji: "🔙",
              category: .discovery, difficulty: .easy, rule: .count(.intakeRemoved), target: 1),
        .init(key: "discover.buttons", title: "Свої кнопки", details: "Кнопки порцій налаштовано", emoji: "🎛️",
              category: .discovery, difficulty: .easy, rule: .count(.presetsChanged), target: 1),
        .init(key: "discover.schedule", title: "Мій графік", details: "Підйом і відбій налаштовано", emoji: "🕰️",
              category: .discovery, difficulty: .easy, rule: .count(.scheduleEdited), target: 1),
        .init(key: "discover.notifications", title: "На звʼязку", details: "Сповіщення дозволено", emoji: "🔔",
              category: .discovery, difficulty: .easy, rule: .count(.notificationAuthorized), target: 1,
              gate: .notifications),
        .init(key: "discover.notificationGlass", title: "Склянка зі сповіщення", details: "Порція кнопкою «+склянка»",
              emoji: "📲", category: .discovery, difficulty: .easy,
              rule: .history(.sourceGroups([[.notification]])), target: 1, gate: .notifications),
        // Віджети, екран блокування й Пункт керування пишуть одне джерело — `.widget`.
        .init(key: "discover.widget", title: "На робочому столі", details: "Порція з віджета", emoji: "🧩",
              category: .discovery, difficulty: .easy, rule: .history(.sourceGroups([[.widget]])), target: 1),
        .init(key: "discover.voice", title: "Голосом", details: "Порція через Siri чи «Команди»", emoji: "🗣️",
              category: .discovery, difficulty: .easy, rule: .history(.sourceGroups([[.siri, .shortcut]])), target: 1),
        .init(key: "discover.allPaths", title: "Усі шляхи",
              details: "Порції із застосунку, віджета, сповіщення й «Команд»", emoji: "🔀",
              category: .discovery, difficulty: .medium,
              rule: .history(.sourceGroups([[.app], [.widget], [.notification], [.siri, .shortcut]])), target: 4,
              gate: .notifications),
        .init(key: "discover.levelChoice", title: "Перехрестя", details: "Обрано приз на шляху рівнів", emoji: "🪜",
              category: .discovery, difficulty: .easy, rule: .game(.levelChoices), target: 1),
        .init(key: "discover.weekReport", title: "Історія тижня", details: "Звіт тижня переглянуто до кінця", emoji: "📖",
              category: .discovery, difficulty: .easy, rule: .count(.weekReportFinished), target: 1),
        .init(key: "discover.monthReport", title: "Підсумки місяця", details: "Звіт місяця переглянуто до кінця",
              emoji: "📚", category: .discovery, difficulty: .medium, rule: .count(.monthReportFinished), target: 1),
        .init(key: "discover.pastDay", title: "Погляд у минуле", details: "Відкрито минулий день у календарі",
              emoji: "🔍", category: .discovery, difficulty: .easy, rule: .count(.pastDayOpened), target: 1),
        .init(key: "discover.dark", title: "Темна сторона", details: "Застосунок у темній темі", emoji: "🌓",
              category: .discovery, difficulty: .easy, rule: .count(.darkTheme), target: 1),
        // Таємне, бо вікно «Графік дня» з'являється не в кожного: відкрите заздалегідь, воно висіло б недосяжним.
        .init(key: "discover.rhythm", title: "Свій ритм", details: "Прийнято пропозицію графіка дня", emoji: "🧭",
              category: .discovery, difficulty: .medium, rule: .count(.scheduleOfferAccepted), target: 1,
              secrecy: .hint("Застосунок помітить твій ритм"))
    ]

    /// §4.8 🎉 Особливі: календар і фанові — 20. Сонцестояння й повня — `SkyCalendar`, без мережі.
    static let special: [AchievementDefinition] = [
        .init(key: "special.weekend", title: "Вихідні в ритмі", details: "Норма в суботу й неділю", emoji: "🎉",
              category: .special, difficulty: .easy, rule: .history(.goalWeekends), target: 1),
        .init(key: "special.weekendMonth", title: "Місяць вихідних", details: "4 вихідних поспіль із нормою в обидва дні",
              emoji: "🏖️", category: .special, difficulty: .medium, rule: .history(.goalWeekendsRun), target: 4),
        .init(key: "special.summer", title: "Літо", details: "30 днів із нормою за червень–серпень", emoji: "☀️",
              category: .special, difficulty: .medium, rule: .history(.seasonGoalDays(.summer)), target: 30),
        .init(key: "special.winter", title: "Зима", details: "30 днів із нормою за грудень–лютий", emoji: "⛄",
              category: .special, difficulty: .medium, rule: .history(.seasonGoalDays(.winter)), target: 30),
        .init(key: "special.seasons", title: "Чотири сезони", details: "30+ днів із нормою в кожному сезоні", emoji: "🍂",
              category: .special, difficulty: .legendary, rule: .history(.seasonsWithGoalDays(minDays: 30)), target: 4),
        .init(key: "special.anniversary", title: "Рік разом", details: "Рік від першої порції — і цього дня є порція",
              emoji: "🎂", category: .special, difficulty: .legendary, rule: .history(.anniversary), target: 1),
        // Правило «8 склянок на день» не має наукового підґрунтя (Valtin, 2002) — досягнення з усмішкою.
        .init(key: "special.eightGlasses", title: "Вісім склянок", details: "8 порцій за день. «8 склянок» — міф, але гарний",
              emoji: "🥛", category: .special, difficulty: .easy, rule: .history(.bestEntriesInDay), target: 8),
        .init(key: "special.halfFull", title: "Склянка наполовину повна", details: "Пів норми до 12:00", emoji: "🫗",
              category: .special, difficulty: .easy, rule: .history(.halfGoalBeforeNoonDays), target: 1),
        .init(key: "special.newYear", title: "Новорічна склянка", details: "Порція 1 січня", emoji: "🎆",
              category: .special, difficulty: .easy, rule: .history(.portionOnDate(month: 1, day: 1)), target: 1,
              secrecy: .hint("Перша склянка року")),
        .init(key: "special.leap", title: "Високосний", details: "Порція 29 лютого", emoji: "🐸",
              category: .special, difficulty: .easy, rule: .history(.portionOnDate(month: 2, day: 29)), target: 1,
              secrecy: .hint("Буває раз на чотири роки")),
        // 22 березня — день ООН із 1993 року.
        .init(key: "special.waterDay", title: "Всесвітній день води", details: "Норма 22 березня", emoji: "🚰",
              category: .special, difficulty: .easy, rule: .history(.goalOnDate(month: 3, day: 22)), target: 1,
              secrecy: .hint("Є день, присвячений воді")),
        .init(key: "special.longestDay", title: "Найдовший день", details: "Норма в день літнього сонцестояння",
              emoji: "🌻", category: .special, difficulty: .easy, rule: .history(.goalOnSolstice(.june)), target: 1,
              secrecy: .hint("Сонце не поспішає сідати")),
        .init(key: "special.shortestDay", title: "Найкоротший день", details: "Норма в день зимового сонцестояння",
              emoji: "🕯️", category: .special, difficulty: .easy, rule: .history(.goalOnSolstice(.december)), target: 1,
              secrecy: .hint("Темніє зовсім рано")),
        .init(key: "special.fullMoon", title: "Повня", details: "Порція в день повного місяця", emoji: "🌕",
              category: .special, difficulty: .easy, rule: .history(.portionOnFullMoon), target: 1,
              secrecy: .hint("Подивись на небо")),
        .init(key: "special.twins", title: "Як дві краплі води", details: "Два дні поспіль однаковий обсяг, до мілілітра",
              emoji: "♊", category: .special, difficulty: .medium, rule: .history(.twinDays), target: 1,
              secrecy: .hint("Вчора й сьогодні — однаково")),
        .init(key: "special.borderless", title: "Вода без кордонів", details: "Порція в іншому часовому поясі", emoji: "✈️",
              category: .special, difficulty: .easy, rule: .history(.otherTimeZone), target: 1,
              secrecy: .hint("Вода всюди однакова")),
        .init(key: "special.thimble", title: "Наперсток", details: "Порція 50 мл", emoji: "🤏",
              category: .special, difficulty: .easy, rule: .history(.portionOfMl(50)), target: 1,
              secrecy: .hint("Іноді досить і ковточка")),
        .init(key: "special.noon", title: "Опівдні", details: "Порція рівно о 12:00", emoji: "🕛",
              category: .special, difficulty: .easy, rule: .history(.portionAtMinute(12 * 60)), target: 1,
              secrecy: .hint("Хвилина в хвилину")),
        .init(key: "special.indecision", title: "Нерішучість", details: "Порцію додано й скасовано тричі за хвилину",
              emoji: "🤔", category: .special, difficulty: .easy, rule: .history(.indecision(times: 3, withinSeconds: 60)),
              target: 1, secrecy: .hint("Додати чи ні?")),
        .init(key: "special.mirror", title: "Дзеркало", details: "За день випито паліндром, як-от 2112 мл", emoji: "🔢",
              category: .special, difficulty: .medium, rule: .history(.palindromeDay(minMl: 1000)), target: 1,
              secrecy: .hint("Читається однаково з обох боків"))
    ]

    /// §4.10 🥚 Пасхалки — 10, невидимі до знахідки. Опис — те, що сталося, без умови: умова не має
    /// потрапити на очі навіть у коді екрана. Половина — водні приказки, умова — буквальне прочитання.
    static let eggs: [AchievementDefinition] = [
        .init(key: "egg.mouthful", title: "Набрати в рот води", details: "Сповіщення мовчать", emoji: "🤐",
              category: .discovery, difficulty: .easy, rule: .count(.notificationPaused), target: 1, secrecy: .egg),
        .init(key: "egg.cleanWater", title: "Вивести на чисту воду", details: "Тепер відомо, звідки береться XP",
              emoji: "🔦", category: .discovery, difficulty: .easy, rule: .count(.xpGuideOpened), target: 1,
              secrecy: .egg),
        // Головний, «Прогрес», «Досягнення», «Призи», «Шлях рівнів», «Статистика», звіт, «Налаштування»,
        // «Сповіщення», «Кнопки порцій» — будь-коли, не обов'язково за день (`AppScreen` у Features).
        .init(key: "egg.fish", title: "Як риба у воді", details: "Кожен куточок застосунку знайомий", emoji: "🐟",
              category: .discovery, difficulty: .easy, rule: .count(.screenOpened), target: 10, secrecy: .egg),
        // Тепліша сестра «Знову тут»: свято за саму першу порцію після місяця, навіть без норми.
        .init(key: "egg.longTime", title: "Багато води утекло", details: "З поверненням!", emoji: "⏳",
              category: .streak, difficulty: .medium, rule: .history(.returnAfterBreak(days: 30)), target: 1,
              secrecy: .egg),
        .init(key: "egg.inseparable", title: "Не розлий вода", details: "Рік щодня з водою", emoji: "🤝",
              category: .regularity, difficulty: .legendary, rule: .history(.activeDaysRun), target: 365,
              secrecy: .egg),
        .init(key: "egg.pi", title: "Пі", details: "314 мл — майже π", emoji: "🥧",
              category: .water, difficulty: .easy, rule: .history(.portionOfMl(314)), target: 1, secrecy: .egg),
        .init(key: "egg.wish", title: "Загадай бажання", details: "Порція об 11:11", emoji: "✨",
              category: .special, difficulty: .easy, rule: .history(.portionAtMinute(11 * 60 + 11)), target: 1,
              secrecy: .egg),
        .init(key: "egg.friday13", title: "П'ятниця, 13-те", details: "Порція в п'ятницю, 13-го — і нічого не сталося",
              emoji: "🐈‍⬛", category: .special, difficulty: .easy, rule: .history(.portionOnFriday13), target: 1,
              secrecy: .egg),
        .init(key: "egg.aprilFools", title: "Це не жарт", details: "Пити воду 1 квітня — не жарт", emoji: "🃏",
              category: .special, difficulty: .easy, rule: .history(.portionOnDate(month: 4, day: 1)), target: 1,
              secrecy: .egg),
        .init(key: "egg.disco", title: "Дискотека", details: "Світло — темно — світло…", emoji: "🪩",
              category: .discovery, difficulty: .easy, rule: .burst(.themeChanged, count: 5, withinSeconds: 60),
              target: 1, secrecy: .egg)
    ]

    public static let all: [AchievementDefinition] = {
        let catalog = water + streaks + regularity + dayRhythm + stats + game + discovery + special + eggs
        // «Усе зібрано» — решта основного каталогу: таємні й залежні від функцій сюди не входять (§4.6).
        let complete = AchievementDefinition(
            key: "collection.all", title: "Усе зібрано", details: "Зібрано весь основний каталог", emoji: "💠",
            category: .game, difficulty: .legendary, rule: .collection(.core),
            target: Double(catalog.filter(\.isCore).count)
        )
        return catalog + [complete]
    }()

    /// Події, після яких варто перерахувати досягнення: метрики правил, зміни історії днів і XP. Решта
    /// (частини доби) умов не змінює.
    static let triggers: Set<MetricKey> = {
        var keys: Set<MetricKey> = [.intakeAdded, .intakeCount, .intakeRemoved, .intakeRestored, .dayGoalMet]
        for definition in all {
            switch definition.rule {
            case .metric(let rule):
                if case .metric(let key, _, _) = rule.source { keys.insert(key) }
            case .burst(let key, _, _):
                keys.insert(key)
            case .level, .history, .game, .collection:
                break
            }
        }
        return keys
    }()

    /// Порядок проходу: колекції — останніми, щоб бачити відкрите в тому самому проході.
    static let evaluationOrder: [AchievementDefinition] = all.filter { !$0.rule.isCollection }
        + all.filter(\.rule.isCollection)

    private static let byKey: [String: AchievementDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.key, $0) }
    )

    public static func definition(_ key: String) -> AchievementDefinition? { byKey[key] }

    /// Стеля вітрини на 3f — два ряди по 4. Три ряди вже зʼїдають екран «Прогресу»,
    /// де досягнення — останній блок, а не головний.
    public static let showcaseLimit = 8

    /// Категорії для меню фільтра на 2e — лише непорожні, у фіксованому порядку.
    /// Псевдо-«Всі» сюди не входить: це відсутність фільтра, її додає екран.
    public static var categories: [AchievementCategory] {
        AchievementCategory.allCases.filter { category in
            all.contains { $0.category == category && !$0.secrecy.isEgg }
        }
    }

    /// Рядок «Пасхалка! Тут їх більше» — у картці першої знайденої пасхалки (§4.10).
    public static let firstEggNote = "Пасхалка! Тут їх більше"
}

// MARK: - Нагороди

public struct RewardDefinition: Sendable, Identifiable {
    public let key: String
    public let kind: RewardKind
    public let title: String
    public let details: String
    public let emoji: String
    /// Лише для бустів: у скільки разів множиться XP до 00:00.
    public let boostFactor: Int?

    public var id: String { key }

    public init(key: String, kind: RewardKind, title: String, details: String, emoji: String, boostFactor: Int? = nil) {
        self.key = key
        self.kind = kind
        self.title = title
        self.details = details
        self.emoji = emoji
        self.boostFactor = boostFactor
    }
}

/// Каталог призів (SPEC-PRIZES §3). Правило каталогу: **не видаємо призів, що нічого
/// не роблять** — «Новий бейдж», «Новий тип завдань» і тема без палітри звідси прибрані.
/// Предмети зі старими ключами не проходять через `definition(_:)` і просто не показуються.
public enum RewardCatalog {
    public static let freezeKey = "streak.freeze"
    public static let boostKey = "xp.double"
    /// 🌟 «Потрійний XP» — лише з таємних призів (SPEC-PRIZES §16.2). Не 💎: діамант читається як валюта.
    public static let tripleKey = "xp.triple"

    /// Порядок — порядок рядків в інвентарі: заморозка, бо цінніша й рідша, потім рідкісний 🌟, потім ⚡.
    public static let all: [RewardDefinition] = [
        RewardDefinition(key: freezeKey, kind: .streakFreeze, title: "Заморозка серії",
                         details: "Пропущений день не обірве серію", emoji: "🧊"),
        RewardDefinition(key: tripleKey, kind: .xpBoost, title: "Потрійний XP",
                         details: "×3 XP до кінця дня", emoji: "🌟", boostFactor: 3),
        RewardDefinition(key: boostKey, kind: .xpBoost, title: "Подвійний XP",
                         details: "×2 XP до кінця дня", emoji: "⚡", boostFactor: 2)
    ]

    /// Усі бусти: одночасно діє лише один з них, будь-який (§7).
    public static let boostKeys = all.filter { $0.kind == .xpBoost }.map(\.key)

    public static func definition(_ key: String) -> RewardDefinition? {
        all.first { $0.key == key }
    }
}
