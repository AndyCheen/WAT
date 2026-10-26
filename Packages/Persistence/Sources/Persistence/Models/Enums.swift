import Foundation

/// Джерело порції — знадобиться для аналітики «скільки додано з віджета» (ТЗ §2).
public enum IntakeSource: Int, Codable, CaseIterable, Sendable {
    case app = 0, widget, notification, siri, shortcut, seed
}

public enum GoalSource: Int, Codable, Sendable {
    case calculated = 0, manual, onboarding, seed
}

public enum ThemeMode: Int, Codable, CaseIterable, Sendable {
    case system = 0, light, dark
}

public enum Gender: Int, Codable, CaseIterable, Sendable {
    case unspecified = 0, male, female
}

public enum ActivityLevel: Int, Codable, CaseIterable, Sendable {
    case low = 0, medium, high

    public var title: String {
        switch self {
        case .low: return "Низька"
        case .medium: return "Середня"
        case .high: return "Висока"
        }
    }
}

public enum ClimateLevel: Int, Codable, CaseIterable, Sendable {
    case moderate = 0, hot

    public var title: String {
        switch self {
        case .moderate: return "Помірний"
        case .hot: return "Спекотний"
        }
    }
}

/// Нові значення — лише в кінець: raw записано в `XPEntry`.
public enum XPReason: Int, Codable, Sendable {
    case intake = 0, questCompleted, achievementUnlocked, dailyGoal, dayPartGoal, prize, streakBonus, levelBonus
    /// «Знову в ритмі» — норма наступного дня після пропуску, що обірвав серію (SPEC-NOTIFICATIONS §12.5 Б).
    case bounceBack
    /// Нараховано з режиму розробника (WAT-68) — повз правила, щоб перевірити рівні й шлях рівнів.
    case debug
}

public enum QuestScope: Int, Codable, CaseIterable, Sendable {
    case daily = 0, weekly, adhoc
}

/// `cancelled` — у кінці, бо raw зберігається: несподіване, скасоване до появи (норму вже закрито), —
/// не проігноване (SPEC-QUESTS §6.4).
public enum QuestState: Int, Codable, Sendable {
    case active = 0, completed, expired, claimed, cancelled
}

/// `questType` і `badge` прибрано (SPEC-PRIZES §3.2): предмет без дії — це досягнення
/// або властивість рівня, а не приз. Raw-значення решти не зсуваються.
public enum RewardKind: Int, Codable, CaseIterable, Sendable {
    case theme = 0, xpBoost, streakFreeze
}

public enum RewardSource: Int, Codable, Sendable {
    case level = 0, quest, achievement, random, seed
    /// Подарунок за повернення після перерви (SPEC-NOTIFICATIONS §12.5 А).
    case comeback
}

/// `ready` раніше звався `new` і плутав «не бачив» із «не використав» — тепер
/// «нове» живе окремо в `RewardItem.seenAt`. Raw 0 лишився, тож збережені записи читаються.
public enum RewardItemState: Int, Codable, Sendable {
    case ready = 0, active, used, expired
}

/// Категорії-фільтри каталогу досягнень (SPEC-ACHIEVEMENTS-CATALOG §3): типів 11, а фільтрів 8 —
/// понад 8 рядків меню вже скролиться. «Повернення» живуть у `.streak`, «Календар» і «Фанові» —
/// в `.special`, «Рівні» — у `.game`. Таємні — прапорець, а не категорія.
///
/// «Всі» тут свідомо немає: це псевдо-таб фільтра, а не категорія. Raw ніде не зберігається —
/// категорію дає визначення в каталозі, тож порядок можна міняти.
public enum AchievementCategory: Int, Codable, CaseIterable, Sendable {
    case water = 0, streak, regularity, dayRhythm, stats, game, discovery, special

    public var title: String {
        switch self {
        case .water: return "Вода"
        case .streak: return "Серії"
        case .regularity: return "Регулярність"
        case .dayRhythm: return "Ритм дня"
        case .stats: return "Статистика"
        case .game: return "Гра"
        case .discovery: return "Відкриття"
        case .special: return "Особливі"
        }
    }
}

public enum MetricPeriodType: Int, Codable, CaseIterable, Sendable {
    case day = 0, week, month, year, all
}

/// Типи сповіщень — каталог SPEC-NOTIFICATIONS §5. Етап A планує 1, 2, 3, 7, 8, 9;
/// 4–6 оголошені наперед для етапів B і C, щоб raw-значення не зсувались.
///
/// Замінив `NotificationKind (smart, fixed, adaptive, analysis)`: то були режими з чекбоксів
/// ТЗ продукту, а не типи, і налаштування за типами в них не вкладались (§2, п. 2).
public enum NotificationType: Int, Codable, CaseIterable, Sendable {
    case reminder = 1, morning, evening, checkpoint, challenge, report, rescue, echo, comeback

    /// Ключ з §5 — частина ідентифікатора `wt.<ключ>.<dayKey>.<слот>`.
    public var key: String {
        switch self {
        case .reminder: return "reminder"
        case .morning: return "morning"
        case .evening: return "evening"
        case .checkpoint: return "checkpoint"
        case .challenge: return "challenge"
        case .report: return "report"
        case .rescue: return "rescue"
        case .echo: return "echo"
        case .comeback: return "comeback"
        }
    }

    public init?(key: String) {
        guard let match = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = match
    }
}

/// Як користувач відповів на сповіщення (§3.2). `none` — ще ніяк.
public enum NotificationResponseKind: Int, Codable, Sendable {
    case none = 0, intake, snooze, pause, open
}

/// «За темпом» — головний режим; «Рівні інтервали» — для тих, хто хоче передбачуваності (§6.2).
public enum ReminderMode: Int, Codable, CaseIterable, Sendable {
    case pace = 0, interval
}

/// Частота нагадувань за темпом — одне налаштування замість трьох чисел (§6.2).
public enum ReminderFrequency: Int, Codable, CaseIterable, Sendable {
    case rarer = 0, normal, more
}

/// Звук сповіщень — окремо від `UserProfile.soundEnabled`, що стосується звуків у застосунку (§14.4).
public enum NotificationSound: Int, Codable, CaseIterable, Sendable {
    case bubble = 0, system, silent
}

/// Шторка «Нагадувати, коли забудеш про воду?» після першої порції (§16.5).
public enum PermissionPromptState: Int, Codable, Sendable {
    /// Ще не показували.
    case notAsked = 0
    /// «Не зараз» — спитаємо ще раз через 3 дні.
    case postponed
    /// Відповідь отримано або вдруге відкладено — далі лише з налаштувань.
    case finished
}

/// Чим закінчився показ вікна «Графік дня» (WAT-41, SPEC-NOTIFICATIONS §27).
public enum ScheduleOfferOutcome: Int, Codable, Sendable {
    /// Ще не показували.
    case none = 0
    /// «Так» чи «Зберегти» — наступна пропозиція не раніше ніж за 30 днів.
    case accepted
    /// «Ні, залишити» — 60 днів, якщо зсув не виріс на ≥ 60 хв.
    case declined
    /// Закрили ✕ або застосунок закрили з відкритим вікном — спитаємо через 7 днів.
    case dismissed
}

/// Особливий стан, що змінює норму (WAT-56, SPEC-ONBOARDING §3.1): EFSA окремо додає воду лише для цих двох.
/// Питається тільки при статі «Жінка»; стан тимчасовий — повторний онбординг його знімає.
public enum BodyCondition: Int, Codable, CaseIterable, Sendable {
    case none = 0, pregnancy, breastfeeding
}

/// Чим закінчився перший онбординг (SPEC-ONBOARDING §6, §8). Не «пройшли / ні»: після «Пропустити»
/// він не відкривається сам, але й пройденим не вважається.
public enum OnboardingState: Int, Codable, Sendable {
    /// Ще не показували — на першому запуску відкриється сам, якщо в базі немає жодної порції.
    case notShown = 0
    case skipped
    case completed
}
