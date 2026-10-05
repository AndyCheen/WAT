import Core
import Insights

/// Тексти вікна «Графік дня» (WAT-41, SPEC-NOTIFICATIONS §27) — чиста функція, як `DayPartPresenter`.
///
/// На «ти», без роду (§14.1). Час — лише в рядках «08:00 → 06:30», а не в заголовку й реченні: перша
/// версія макета повторювала «06:30» тричі. «2 тижні» й «два вихідні» — вікно `ScheduleShiftRules.windowDays`.
enum SchedulePresenter {
    struct Change: Equatable, Identifiable {
        enum Bound: String, Equatable { case wake, sleep }
        let bound: Bound
        let glyph: String
        let old: String
        let new: String
        let accessibilityLabel: String
        var id: Bound { bound }
    }

    struct Content: Equatable {
        let glyph: String
        /// «Лише вихідні» — коли змінюється не весь графік.
        let scope: String?
        let title: String
        let subtitle: String
        /// Лише ті межі, що змінюються.
        let changes: [Change]
    }

    static let wakeGlyph = "☀️"
    static let sleepGlyph = "🌙"

    /// `draft` — що буде збережено: пропозиція або підправлене в «Налаштувати».
    static func content(_ suggestion: ScheduleSuggestion, draft: DaySchedule) -> Content {
        let current = suggestion.current, proposed = suggestion.proposed
        let wake = proposed.wakeMinutes != current.wakeMinutes
        let sleep = proposed.sleepMinutes != current.sleepMinutes
        let morning = proposed.wakeMinutes < current.wakeMinutes ? "раніше" : "пізніше"
        let evening = proposed.sleepMinutes > current.sleepMinutes ? "пізніше" : "раніше"

        let when: String
        switch suggestion.scope {
        case .everyDay: when = "Останні 2 тижні"
        case .weekdays, .weekdaysOnly: when = "Останні 2 тижні в будні"
        case .weekends: when = "Останні два вихідні"
        }
        let subtitle: String
        switch (wake, sleep) {
        case (true, true): subtitle = "\(when) ти починаєш пити \(morning), а закінчуєш \(evening)"
        case (true, false): subtitle = "\(when) ти починаєш пити \(morning)"
        default: subtitle = "\(when) ти закінчуєш пити \(evening)"
        }

        var changes: [Change] = []
        if wake {
            changes.append(change(.wake, title: "Підйом", glyph: wakeGlyph, old: current.wakeMinutes, new: draft.wakeMinutes))
        }
        if sleep {
            changes.append(change(.sleep, title: "Відбій", glyph: sleepGlyph, old: current.sleepMinutes, new: draft.sleepMinutes))
        }

        return Content(
            glyph: wake && sleep ? "🕰️" : wake ? wakeGlyph : sleepGlyph,
            scope: scopeTitle(suggestion.scope),
            title: wake && sleep ? "Змінити графік?" : wake ? "Змінити підйом?" : "Змінити відбій?",
            subtitle: subtitle,
            changes: changes
        )
    }

    /// Тост після «Так»: «Графік оновлено: 06:30–22:00».
    static func toast(_ suggestion: ScheduleSuggestion, schedule: DaySchedule) -> String {
        switch suggestion.scope {
        case .everyDay: return "Графік оновлено: \(schedule.label)"
        case .weekdays, .weekdaysOnly: return "Графік буднів оновлено: \(schedule.label)"
        case .weekends: return "Графік вихідних оновлено: \(schedule.label)"
        }
    }

    private static func scopeTitle(_ scope: ScheduleSuggestion.Scope) -> String? {
        switch scope {
        case .everyDay: return nil
        case .weekdays, .weekdaysOnly: return "Лише будні"
        case .weekends: return "Лише вихідні"
        }
    }

    private static func change(_ bound: Change.Bound, title: String, glyph: String, old: Int, new: Int) -> Change {
        let old = DaySchedule.clock(old), new = DaySchedule.clock(new)
        return Change(bound: bound, glyph: glyph, old: old, new: new,
                      accessibilityLabel: "\(title): було \(old), стане \(new)")
    }
}
