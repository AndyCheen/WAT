import Foundation

/// Дія з віджета, елемента керування чи «Команд». Порції виконуються в процесі застосунку: інтенти — це
/// `LiveActivityIntent` (SPEC-WIDGETS §9.2), а обробляє їх `AppServices.perform(_:)`. Розгортання вибору «Інше» —
/// стан самого віджета, його веде розширення без застосунку (`WidgetCustomPicker`).
public enum WidgetAction: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// Віджет або елемент Пункту керування — `IntakeSource.widget`.
        case widget
        /// «Команди» — `IntakeSource.shortcut`.
        case shortcut
    }

    case add(ml: Int, source: Source)
    /// «Скасувати» — лише порцію, яку щойно додав віджет.
    case undo(intakeId: UUID)
    /// «Інше» — розгорнути у віджеті підказки зі шторки «Інше» (рішення від 09.10.2026).
    case showCustomPicker(WidgetKind)
    /// ✕ — згорнути підказки.
    case hideCustomPicker(WidgetKind)
}
