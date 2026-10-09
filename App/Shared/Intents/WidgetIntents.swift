import AppIntents
import Widgets

// Дії кнопок віджетів і елемента Пункту керування (WAT-30, SPEC-WIDGETS §9.2).
//
// Виконуються в процесі застосунку (а якщо той закритий — система запускає його у фоні). Тож порція йде
// звичайним доменним стеком — з тими самими кешами метрик і гейміфікації, `commit()`, переплануванням і
// відлунням, — а розширення віджетів SwiftData не відкриває зовсім.
//
// У процес застосунку інтент відправляє `ForegroundContinuableIntent` — оголошений в обох цілях, але
// недоступний у розширенні (`@available(iOSApplicationExtension, unavailable)`, внизу файлу). Звичайний
// `AppIntent` пішов би в розширення, коли застосунок не працює. `LiveActivityIntent` теж іде в застосунок,
// але з ним кожен тап коштував ~3 с: «Команди» дають застосунку дозвіл почати Live Activity й чекають на неї
// 3 с, перш ніж повідомити WidgetKit про кінець дії, — а до того віджет не оновлюється (SPEC-WIDGETS §12).
// На екран застосунок не виходить: `requestToContinueInForeground` не викликаємо.
//
// Файл компілюється в обидві цілі: розширенню тип потрібен для `Button(intent:)`, але `perform()` там не
// викликається ніколи — тому тіло лише в застосунку (`WIDGET_EXTENSION` — прапорець цілі розширення).

struct AddWaterWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Додати воду з віджета"
    // У «Командах» — окрема дія `AddWaterIntent` зі своїм джерелом порції.
    static let isDiscoverable = false

    @Parameter(title: "Об'єм, мл")
    var amountMl: Int

    init() {}

    init(ml: Int) {
        amountMl = ml
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        // Порція з підказки «Інше» згортає вибір — після неї віджет показує «Скасувати», а не підказки.
        WidgetCustomPicker.shared.closeAll()
        AppContainer.finishInBackground(await AppContainer.services.perform(.add(ml: amountMl, source: .widget)))
        #endif
        return .result()
    }
}

struct UndoWaterWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Скасувати порцію з віджета"
    static let isDiscoverable = false

    /// `UUID` рядком: серед типів параметрів App Intents його немає.
    @Parameter(title: "Порція")
    var intakeId: String

    init() {}

    init(intakeId: UUID) {
        self.intakeId = intakeId.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        if let id = UUID(uuidString: intakeId) {
            AppContainer.finishInBackground(await AppContainer.services.perform(.undo(intakeId: id)))
        }
        #endif
        return .result()
    }
}

// Лише конформність, у тому самому файлі: метадані інтенту в обох цілях мають її бачити, інакше розширення
// виконає дію в себе — а там `perform()` порожній.
@available(iOSApplicationExtension, unavailable)
extension AddWaterWidgetIntent: ForegroundContinuableIntent {}

@available(iOSApplicationExtension, unavailable)
extension UndoWaterWidgetIntent: ForegroundContinuableIntent {}
