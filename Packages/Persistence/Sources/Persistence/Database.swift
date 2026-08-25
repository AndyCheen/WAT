import Foundation
import SwiftData
import Core

/// Опис схеми та фабрика контейнера SwiftData.
///
/// Уся схема зібрана в одному місці — це ж місце буде точкою входу для міграцій.
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
        NotificationRule.self
    ])

    /// Версія схеми. Підвищується разом з появою `SchemaMigrationPlan`.
    public static let currentVersion = Schema.Version(1, 0, 0)

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(
            "WaterTracker",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
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
}
