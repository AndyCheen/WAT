import Foundation
import Core
import Persistence
import Hydration
import Gamification

/// Детерміновані демо-дані: історія за 60 днів + сьогоднішній день як у макетах.
/// Використовується в дизайн-QA, превʼю та e2e-тестах (PLAN.md §9).
@MainActor
public enum FixtureSeeder {

    /// Сьогоднішні порції з макета 1a: 250 / 500 / 200 / 300 → 1250 мл.
    public static let todayIntakes: [(hour: Int, minute: Int, ml: Int)] = [
        (8, 15, 250), (10, 40, 500), (12, 5, 200), (14, 20, 300)
    ]

    public static func seed(into services: AppServices, days: Int = 60) {
        let calendar = services.calendar
        let today = calendar.today

        services.profiles.setGoal(
            2000, source: .seed,
            effectiveFrom: calendar.dayKey(offsetDays: -days - 1, from: today),
            at: calendar.now
        )

        // Історія: у кожен день кілька порцій за псевдовипадковим, але стабільним патерном.
        for offset in stride(from: days, through: 1, by: -1) {
            let dayKey = calendar.dayKey(offsetDays: -offset, from: today)
            let date = calendar.date(from: dayKey)
            let seed = stableHash(dayKey.rawValue)

            // Учора пропущено, а позавчора норму закрито — сценарій «заморозити вчора»
            // (SPEC-PRIZES §11): e2e перевіряє обидва тексти кнопки заморозки.
            if offset == 1 { continue }

            // Кожен 9-й день пропускаємо — щоб серії й календар мали розриви.
            if seed % 9 == 0, offset != 2 { continue }

            // Пропуск і патерн беремо з різних половин хешу: спільне джерело остач
            // корелює (9 і 6 мають дільник 3) і перекошує частку днів із закритою нормою.
            let pattern = offset == 2
                ? patterns[0]
                : patterns[Int((seed >> 32) % UInt64(patterns.count))]
            for entry in pattern {
                var components = DateComponents()
                components.year = dayKey.year
                components.month = dayKey.month
                components.day = dayKey.day
                components.hour = entry.hour
                components.minute = entry.minute
                guard let stamp = calendar.calendar.date(from: components) else { continue }
                services.hydration.addIntake(amountMl: entry.ml, source: .seed, at: stamp)
            }
            _ = date
        }

        for entry in todayIntakes {
            var components = calendar.calendar.dateComponents([.year, .month, .day], from: calendar.now)
            components.hour = entry.hour
            components.minute = entry.minute
            guard let stamp = calendar.calendar.date(from: components), stamp <= calendar.now else { continue }
            services.hydration.addIntake(amountMl: entry.ml, source: .seed, at: stamp)
        }

        services.gamification.refresh(at: calendar.now)
        settleLevelRoad(services)
        topUpPrizes(services)
        // Патерн дня залежить від дати, а e2e біжать на справжньому годиннику: у якийсь із днів 14-денне вікно
        // могло б скластися в зсув, і вікно «Графік дня» перекрило б чужий сценарій. Демо-історія вважається
        // такою, що вже відповіла «Так»; саме вікно — `--start-screen schedule-suggestion` (WAT-41).
        services.profile.scheduleOfferShownAt = calendar.now
        services.profile.scheduleOfferOutcome = .accepted
        services.profiles.save()
        services.touch()
    }

    /// `--seed-schedule-shift` — критерій приймання WAT-41 для e2e: 10 із 14 днів перша склянка ≈ 06:30 при
    /// підйомі 08:00, і вікно «Графік дня» з'являється на відкритті саме. Окремо від демо-історії: там
    /// зсуву свідомо немає, інакше вікно перекривало б інші сценарії.
    public static func seedScheduleShift(into services: AppServices) {
        let calendar = services.calendar
        for offset in 1...14 where ![3, 6, 10, 13].contains(offset) {
            let day = calendar.dayKey(offsetDays: -offset, from: calendar.today)
            for (hour, minute, ml) in [(6, 20 + offset % 4 * 5, 250), (13, 0, 500), (20, 30, 300)] {
                let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
                guard let stamp = calendar.calendar.date(from: parts) else { continue }
                services.hydration.addIntake(amountMl: ml, source: .seed, at: stamp)
            }
        }
        services.gamification.refresh(at: calendar.now)
        services.touch()
    }

    /// За 60 днів демо проходить два десятки рівнів, і всі вибори й 🎁 чекали б дії. Як у живої людини,
    /// старі забрано, а чекає по одному вузлу кожного виду — останній вибір і останній таємний: на донаті
    /// крапка «нове», а e2e мають на чому перевірити і вибір, і скриню (SPEC-PRIZES §16.6). Вибір — по
    /// черзі 🧊 і ⚡, щоб на драбині було видно обидва.
    private static func settleLevelRoad(_ services: AppServices) {
        let pending = services.gamification.levelRoad().pending
        let keep = Set([
            pending.last { if case .choice? = $0.reward { return true } else { return false } }?.level,
            pending.last { if case .mystery? = $0.reward { return true } else { return false } }?.level
        ].compactMap { $0 })
        for (index, node) in pending.enumerated() where !keep.contains(node.level) {
            switch node.reward {
            case .choice(let grants)?:
                services.gamification.claimChoice(level: node.level, key: grants[index % grants.count].key)
            case .mystery?:
                services.gamification.openMystery(level: node.level)
            case .prize?, nil:
                break
            }
        }
    }

    /// Демо-інвентар: щонайменше 2 заморозки (обидва тексти кнопки) і 1 буст.
    /// Рівні видають призи й самі, але скільки саме — залежить від дати запуску.
    private static func topUpPrizes(_ services: AppServices) {
        let ready = services.gamification.prizeInventory().ready
        let minimum = [RewardCatalog.freezeKey: 2, RewardCatalog.boostKey: 1]
        for (key, count) in minimum {
            let have = ready.first { $0.key == key }?.count ?? 0
            for _ in 0..<max(0, count - have) {
                services.gamification.grantPrize(key: key, source: .seed)
            }
        }
    }

    /// FNV-1a з `Core` — не `String.hashValue`, що засівається випадково на кожен запуск
    /// процесу (PLAN.md, «Що з'ясувалося», п. 9).
    static func stableHash(_ string: String) -> UInt64 { StableHash.fnv1a(string) }

    /// Патерни підібрані так, щоб приблизно 2 з 3 днів закривали норму 2000 мл —
    /// інакше календар, серії й теплокарта виглядають неправдоподібно порожніми.
    private static let patterns: [[(hour: Int, minute: Int, ml: Int)]] = [
        [(7, 30, 250), (10, 15, 500), (13, 40, 500), (16, 20, 300), (19, 10, 500)],   // 2050
        [(8, 0, 200), (11, 30, 300), (14, 0, 500), (18, 45, 500)],                    // 1500
        [(9, 10, 500), (12, 25, 500), (15, 50, 500), (20, 5, 500)],                   // 2000
        [(6, 45, 200), (9, 30, 250), (12, 0, 1000), (17, 15, 500), (21, 0, 200)],     // 2150
        [(10, 0, 500), (14, 30, 500), (19, 30, 500)],                                 // 1500
        [(8, 20, 350), (11, 0, 350), (13, 15, 500), (16, 40, 350), (18, 20, 350), (22, 10, 200)] // 2100
    ]
}
