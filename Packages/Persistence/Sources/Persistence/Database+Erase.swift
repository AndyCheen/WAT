import Foundation
import SwiftData

/// Що стирає режим розробника (WAT-68).
public enum EraseScope: String, CaseIterable, Sendable {
    /// Порції, гра й журнали. Налаштування людини — профіль, норма, розклад, кнопки, сповіщення — лишаються.
    case progress
    /// Усе — як нова установка: наступний запуск відкриє онбординг.
    case everything
}

extension Database {
    /// Прогрес: від нього похідне все, що бачить людина в грі й статистиці. `LearnProgress` — теж: «нове» на
    /// обкладинках і досягнення «Знань» мають почати з нуля разом із рештою.
    static let progressModels: [any PersistentModel.Type] = [
        DayLog.self, Intake.self, MetricEventRecord.self, MetricCounterRecord.self, XPEntry.self, LevelState.self,
        StreakState.self, QuestInstance.self, AchievementProgress.self, RewardItem.self, NotificationLog.self,
        LearnProgress.self
    ]

    /// Налаштування — те, що людина виставила сама.
    static let settingsModels: [any PersistentModel.Type] = [
        UserProfile.self, GoalRevision.self, QuickAddPreset.self, QuietPeriod.self, NotificationSettings.self
    ]

    /// Стирає дані **до** того, як їх прочитали сервіси: у сервісів кеші й живі об'єкти SwiftData (профіль), і стерти
    /// з-під них на ходу — це падіння на першому ж читанні. Тому режим розробника лише просить стирання, а виконує його
    /// `AppContainer` на наступному запуску.
    ///
    /// Поштучно, а не пакетним `context.delete(model:)`: так спрацьовують правила зв'язків (порції дня йдуть за ним),
    /// а записів у живій базі — тисячі, не мільйони.
    public static func erase(_ scope: EraseScope, in context: ModelContext) throws {
        let models = scope == .everything ? progressModels + settingsModels : progressModels
        for model in models { try deleteAll(model, in: context) }
        if scope == .progress, let profile = try context.fetch(FetchDescriptor<UserProfile>()).first {
            // Стан гри в профілі: без скидання вікно відкриття вважало б рівні вже відсвяткованими, а пропозиція
            // графіка мовчала б ще 60 днів після «Ні».
            profile.celebrationsSince = nil
            profile.highestCelebratedLevel = 0
            profile.scheduleOfferShownAt = nil
            profile.scheduleOfferOutcome = .none
            profile.scheduleOfferShiftMinutes = 0
        }
        try context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ model: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) where !object.isDeleted {
            context.delete(object)
        }
    }
}
