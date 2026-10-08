import AppIntents
import Widgets

// Дії кнопок віджетів і елемента Пункту керування (WAT-30, SPEC-WIDGETS §9.2).
//
// `LiveActivityIntent` — не заради Live Activity: за документацією Apple такий інтент система виконує
// в процесі застосунку (а якщо той закритий — запускає його у фоні). Тож порція йде звичайним доменним
// стеком — з тими самими кешами метрик і гейміфікації, `commit()`, переплануванням і відлунням, — а
// розширення віджетів SwiftData не відкриває зовсім.
//
// Файл компілюється в обидві цілі: розширенню тип потрібен для `Button(intent:)`, але `perform()` там не
// викликається ніколи — тому тіло лише в застосунку (`WIDGET_EXTENSION` — прапорець цілі розширення).

struct AddWaterWidgetIntent: LiveActivityIntent {
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
        await AppContainer.services.perform(.add(ml: amountMl, source: .widget))
        #endif
        return .result()
    }
}

struct UndoWaterWidgetIntent: LiveActivityIntent {
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
            await AppContainer.services.perform(.undo(intakeId: id))
        }
        #endif
        return .result()
    }
}
