import Foundation
import SwiftData
import Core

/// Опис схеми та фабрика контейнера SwiftData.
///
/// Уся схема зібрана в одному місці — це ж місце буде точкою входу для міграцій.
///
/// **Рішення від 25.10.2026 (WAT-67):** `VersionedSchema` поки не заводимо. З планом міграцій SwiftData відкриває
/// лише сховище відомої версії, тож кожне нове поле вимагало б нової версії з копіями всіх моделей — забута версія
/// і є тією втратою даних, від якої захищаємось. Без плану легка міграція сама впорається з новим полем, якщо воно
/// опційне або має значення за замовчуванням, і з перейменуванням через `@Attribute(originalName:)`. Решту страхує
/// копія сховища перед першим відкриттям зміненої схеми (`backupIfSchemaChanged`) і екран помилки замість тихої
/// бази в пам'яті (`AppContainer`).
public enum Database {
    public static let schema = Schema([
        UserProfile.self,
        GoalRevision.self,
        DayLog.self,
        Intake.self,
        MetricEventRecord.self,
        MetricCounterRecord.self,
        XPEntry.self,
        LevelState.self,
        StreakState.self,
        QuestInstance.self,
        AchievementProgress.self,
        RewardItem.self,
        QuickAddPreset.self,
        QuietPeriod.self,
        NotificationSettings.self,
        NotificationLog.self,
        LearnProgress.self
    ])

    /// Версія схеми. Підвищується разом з появою `SchemaMigrationPlan`.
    public static let currentVersion = Schema.Version(1, 0, 0)

    static let storeName = "WaterTracker"

    /// - Parameter url: файл сховища — для тестів; без нього — типовий `Application Support/WaterTracker.store`.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(storeName, schema: schema, url: url)
        } else {
            config = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Контейнер для тестів і превʼю — завжди чистий, нічого не пише на диск.
    public static func makeInMemoryContainer() -> ModelContainer {
        do {
            return try makeContainer(inMemory: true)
        } catch {
            fatalError("Не вдалося створити in-memory контейнер: \(error)")
        }
    }

    /// Де лежить сховище застосунку.
    public static var defaultStoreURL: URL {
        ModelConfiguration(storeName, schema: schema).url
    }

    // MARK: - Резервна копія (WAT-67)

    /// Відбиток схеми: сутності з полями й типами. Змінюється разом із будь-якою моделлю — саме тоді, коли
    /// SwiftData мігрує сховище.
    public static func fingerprint(of schema: Schema = schema) -> String {
        let entities = schema.entities.map { entity in
            let attributes = entity.attributes.map { "\($0.name):\(String(describing: $0.valueType))" }
            let relationships = entity.relationships.map { "\($0.name)->\($0.destination)" }
            return entity.name + "{" + (attributes + relationships).sorted().joined(separator: ",") + "}"
        }
        return StableHash.fnv1a(entities.sorted().joined(separator: ";")).description
    }

    /// Ключ `UserDefaults` з відбитком схеми, з якою сховище відкривали востаннє.
    static let fingerprintKey = "wt.store.schemaFingerprint"
    /// Скільки копій тримати: кожна — повне сховище, а давніша за третю зміну схеми вже нікому не потрібна.
    static let backupsKept = 3

    /// Перед першим відкриттям сховища новою схемою — копія файлів сховища в `Backups/<час>-<відбиток>/`.
    /// Невдала міграція чи збірка з помилкою в моделі тоді не забирає історію: файли можна повернути. Нічого не
    /// робить, якщо сховища ще немає (перший запуск) або схема та сама. Повертає теку копії.
    @discardableResult
    public static func backupIfSchemaChanged(
        storeURL: URL = defaultStoreURL,
        fingerprint current: String = fingerprint(),
        defaults: UserDefaults = .standard,
        now: Date
    ) -> URL? {
        let fileManager = FileManager.default
        guard defaults.string(forKey: fingerprintKey) != current else { return nil }
        guard fileManager.fileExists(atPath: storeURL.path) else {
            defaults.set(current, forKey: fingerprintKey)
            return nil
        }
        let backups = storeURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let stamp = Int(now.timeIntervalSince1970)
        let target = backups.appendingPathComponent("\(stamp)-\(current)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            // SQLite тримає частину даних у -wal і -shm: без них копія неповна.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent))
            }
        } catch {
            // Копія не вдалась — відбиток не пишемо: наступний запуск спробує знову.
            AppLog.persistence.error("backup: \(error)")
            return nil
        }
        pruneBackups(in: backups)
        defaults.set(current, forKey: fingerprintKey)
        return target
    }

    private static func pruneBackups(in directory: URL) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        // Ім'я починається з часу копії — давніші йдуть першими.
        let sorted = entries.sorted { (Int($0.prefix { $0.isNumber }) ?? 0) < (Int($1.prefix { $0.isNumber }) ?? 0) }
        for name in sorted.dropLast(backupsKept) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
