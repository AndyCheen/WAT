import Foundation
import Core
import Persistence
import Hydration

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

            // Кожен 9-й день пропускаємо — щоб серії й календар мали розриви.
            if seed % 9 == 0 { continue }

            // Пропуск і патерн беремо з різних половин хешу: спільне джерело остач
            // корелює (9 і 6 мають дільник 3) і перекошує частку днів із закритою нормою.
            let pattern = patterns[Int((seed >> 32) % UInt64(patterns.count))]
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

        // Два призи в інвентарі — як на макеті 3f.
        services.gamification.refresh(at: calendar.now)
        services.touch()
    }

    /// FNV-1a — хеш, стабільний між запусками процесу.
    ///
    /// Тут був `String.hashValue`, а він у Swift засівається випадково при старті
    /// процесу (без `SWIFT_DETERMINISTIC_HASHING`). Через це «детерміновані» демо-дані
    /// виходили різними на кожен прогін: три однакові запуски з тим самим `FixedClock`
    /// давали серії 0, 2 і 1, а число серії в шапці стрибало між 8 і 9 — це вже
    /// коштувало одного хибного баг-репорту. Дизайн-QA, скріншоти та e2e, що
    /// спираються на вміст демо-історії, вимагають повторюваності.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

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
