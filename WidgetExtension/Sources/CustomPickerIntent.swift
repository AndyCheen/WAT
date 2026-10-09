import AppIntents
import Core
import Widgets

/// «Інше» й ✕ у віджеті — розгорнути чи згорнути підказки (рішення від 09.10.2026, SPEC-WIDGETS §4.3).
///
/// Звичайний `AppIntent`, не `LiveActivityIntent`: це стан самого віджета, тож він виконується в розширенні без
/// запуску застосунку — розгортання майже миттєве. Лише в цілі розширення.
struct CustomPickerIntent: AppIntent {
    static let title: LocalizedStringResource = "Вибір «Інше» у віджеті"
    static let isDiscoverable = false

    @Parameter(title: "Віджет")
    var kind: String

    @Parameter(title: "Розгорнути")
    var open: Bool

    init() {}

    init(kind: WidgetKind, open: Bool) {
        self.kind = kind.rawValue
        self.open = open
    }

    func perform() async throws -> some IntentResult {
        guard let kind = WidgetKind(rawValue: kind) else { return .result() }
        if open {
            WidgetCustomPicker.shared.open(kind, at: SystemClock().now)
        } else {
            WidgetCustomPicker.shared.close(kind)
        }
        return .result()
    }
}
