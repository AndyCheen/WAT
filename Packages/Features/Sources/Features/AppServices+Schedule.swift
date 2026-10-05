import Foundation
import Core
import Persistence
import Hydration
import Insights

/// Пропозиція змінити графік дня (WAT-41, SPEC-NOTIFICATIONS §27): зсув рахує `Insights`, частоту —
/// `ScheduleOfferPolicy`, а застосування живе тут, бо зачіпає `Hydration` (знімок розкладу дня) і сповіщення.
extension AppServices {

    /// Пропозиція, якщо її можна показати сьогодні: зсув є, і правило частоти дозволяє.
    public func scheduleOffer() -> ScheduleSuggestion? {
        guard let suggestion = insights.scheduleSuggestion() else { return nil }
        let profile = self.profile
        let daysSinceShown = profile.scheduleOfferShownAt.map {
            calendar.daysBetween(calendar.dayKey(for: $0), calendar.today)
        }
        let allowed = ScheduleOfferPolicy.canOffer(
            shift: suggestion.shiftMinutes, last: profile.scheduleOfferOutcome,
            daysSinceShown: daysSinceShown, answeredShift: profile.scheduleOfferShiftMinutes
        )
        return allowed ? suggestion : nil
    }

    /// Показ одразу пишеться як «закрили без відповіді»: застосунок можуть закрити з відкритим вікном,
    /// і тоді спитаємо через 7 днів, а не на наступному ж відкритті.
    public func markScheduleOfferShown(_ suggestion: ScheduleSuggestion) {
        let profile = self.profile
        profile.scheduleOfferShownAt = calendar.now
        profile.scheduleOfferOutcome = .dismissed
        profile.scheduleOfferShiftMinutes = suggestion.shiftMinutes
        profiles.save()
    }

    /// «Так» чи «Зберегти». Розклад сьогодні — у запис дня, минулі дні лишаються зі своїми знімками
    /// (WAT-39): звіти й нарахований XP не переписуються. Сповіщення переплановуються одразу.
    public func acceptScheduleOffer(_ suggestion: ScheduleSuggestion, schedule: DaySchedule) {
        let profile = self.profile
        profile.weekSchedule = suggestion.applying(schedule, to: profile.weekSchedule)
        profile.scheduleOfferOutcome = .accepted
        profiles.save()
        hydration.scheduleDidChange()
        touch()
    }

    /// «Ні, залишити» — 60 днів тиші, якщо звичка не відійде ще на годину.
    public func declineScheduleOffer() {
        profile.scheduleOfferOutcome = .declined
        profiles.save()
    }

    /// `--start-screen schedule-suggestion[:варіант]` — вікно одразу, повз правило частоти:
    /// дизайн-QA й e2e не мають чекати двох тижнів історії.
    public func showScheduleSuggestion(_ demo: ScheduleSuggestionDemo) {
        router.openScheduleSuggestion(demo.suggestion(for: profile.weekSchedule))
    }
}

/// Варіанти вікна для `--start-screen schedule-suggestion:<варіант>` — сценарії макета Design/Schedule.html.
public enum ScheduleSuggestionDemo: String, CaseIterable, Sendable {
    case wakeEarly = "wake-early"
    case wakeLate = "wake-late"
    case sleepLate = "sleep-late"
    case sleepEarly = "sleep-early"
    case both
    case weekend
    case weekdays

    func suggestion(for week: WeekSchedule) -> ScheduleSuggestion {
        let weekday = week.weekday
        let everyDay: ScheduleSuggestion.Scope = week.weekendEnabled ? .weekdays : .everyDay
        switch self {
        case .wakeEarly: return ScheduleSuggestion(scope: everyDay, current: weekday, proposed: Self.moved(weekday, wake: -90))
        case .wakeLate: return ScheduleSuggestion(scope: everyDay, current: weekday, proposed: Self.moved(weekday, wake: 105))
        case .sleepLate: return ScheduleSuggestion(scope: everyDay, current: weekday, proposed: Self.moved(weekday, sleep: 75))
        case .sleepEarly: return ScheduleSuggestion(scope: everyDay, current: weekday, proposed: Self.moved(weekday, sleep: -60))
        case .both: return ScheduleSuggestion(scope: everyDay, current: weekday, proposed: Self.moved(weekday, wake: -90, sleep: 75))
        case .weekend:
            let weekend = week.schedule(isWeekend: true)
            return ScheduleSuggestion(scope: .weekends, current: weekend, proposed: Self.moved(weekend, wake: 120))
        case .weekdays:
            return ScheduleSuggestion(scope: week.weekendEnabled ? .weekdays : .weekdaysOnly, current: weekday,
                                      proposed: Self.moved(weekday, wake: -90))
        }
    }

    private static func moved(_ schedule: DaySchedule, wake: Int = 0, sleep: Int = 0) -> DaySchedule {
        DaySchedule(wakeMinutes: max(DaySchedule.earliestWakeMinutes, schedule.wakeMinutes + wake),
                    sleepMinutes: min(DaySchedule.latestSleepMinutes, schedule.sleepMinutes + sleep))
    }
}
