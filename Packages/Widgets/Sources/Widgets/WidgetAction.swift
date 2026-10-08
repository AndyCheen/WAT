import Foundation

/// Дія з віджета, елемента керування чи «Команд». Виконується в процесі застосунку: інтенти — це
/// `LiveActivityIntent` (SPEC-WIDGETS §9.2), а обробляє їх `AppServices.perform(_:)`.
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
}
