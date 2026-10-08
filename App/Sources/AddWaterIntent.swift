import AppIntents
import Widgets

/// Дія «Додати воду» в «Командах» (SPEC-WIDGETS §6): автоматизації на кшталт «після тренування — +500 мл»
/// чи NFC-мітки на пляшці. Лише в цілі застосунку — тож і виконується в ньому, як і кнопки віджетів.
/// Голосових фраз немає: Siri українською не говорить.
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Додати воду"
    static let description = IntentDescription("Додає порцію води, не відкриваючи застосунок.")

    @Parameter(title: "Об'єм, мл", default: 250, inclusiveRange: (50, 2000))
    var amountMl: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Додати \(\.$amountMl) мл води")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppContainer.services.perform(.add(ml: amountMl, source: .shortcut))
        return .result(dialog: "Додано \(amountMl) мл")
    }
}
