import Foundation
import Observation
import SwiftUI
import Core
import Insights
import Gamification
import DesignSystem

/// Модель звіту-історії. Звіт рахується на льоту (§11.3) — при відкритті й при переході між
/// періодами; поки екран відкритий, дані не змінюються, тож `epoch` не слухаємо.
@MainActor
@Observable
final class ReportViewModel {
    private let services: AppServices
    /// Злите «Підсумки тижня й місяця» — два періоди: тиждень, потім «Далі: травень ›».
    private(set) var periods: [ReportPeriod]
    private(set) var position = 0
    var slideIndex = 0
    private(set) var slides: [ReportSlide] = []
    private(set) var header = ""
    private(set) var previousTitle = ""

    /// Без періодів — звіт за минулий тиждень (`--start-screen report`).
    init(services: AppServices, periods: [ReportPeriod]) {
        self.services = services
        let calendar = services.calendar
        self.periods = periods.isEmpty
            ? [calendar.period(.week, containing: calendar.dayKey(offsetDays: -7, from: calendar.today))]
            : periods
        load()
    }

    var period: ReportPeriod { periods[position] }

    /// «Далі: травень ›» — наступний період злитого звіту.
    var nextTitle: String? {
        guard position + 1 < periods.count else { return nil }
        switch periods[position + 1] {
        case .day(let day): return "Далі: \(day.day) \(ReportFormat.monthGenitive(day.month)) ›"
        case .week: return "Далі: тиждень ›"
        case .month(let month): return "Далі: \(ReportFormat.monthName(month.month).lowercased()) ›"
        }
    }

    func showNext() {
        guard position + 1 < periods.count else { return }
        position += 1
        restart()
    }

    func showPrevious() {
        periods[position] = services.calendar.shifted(period, by: -1)
        restart()
    }

    private func restart() {
        withAnimation(WTAnimation.fade) {
            slideIndex = 0
            load()
        }
    }

    private func load() {
        let calendar = services.calendar
        let report = services.insights.report(for: period)
        let days = calendar.days(in: period)
        let profile = services.profile
        let first = days.first ?? calendar.today
        let last = days.last ?? calendar.today

        let presenter = ReportPresenter(
            report: report,
            game: services.gamification.periodSummary(days: days),
            streak: services.gamification.streakSummary(),
            recentGoalDays: calendar.recentDays(7, endingAt: last).map { services.hydration.snapshot(for: $0).goalMet },
            schedule: profile.schedule(isWeekend: calendar.isWeekend(first)),
            weekendScheduleEnabled: profile.weekendScheduleEnabled,
            dayPartXp: services.gamification.xp.rules.perDayPartGoal,
            today: calendar.today,
            tomorrowMorning: tomorrowMorning(after: last),
            nowMinute: period == .day(calendar.today) ? minuteNow : nil,
            calendar: calendar
        )
        slides = presenter.slides
        header = presenter.header
        previousTitle = presenter.previousTitle
    }

    private var minuteNow: Int {
        let parts = services.calendar.calendar.dateComponents([.hour, .minute], from: services.calendar.now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Ранкова склянка завтра — о підйомі або у свій час (§7).
    private func tomorrowMorning(after day: DayKey) -> String? {
        let calendar = services.calendar
        guard day == calendar.today, services.notifications.settings.morningEnabled else { return nil }
        let tomorrow = calendar.dayKey(offsetDays: 1, from: day)
        let wake = services.profile.schedule(isWeekend: calendar.isWeekend(tomorrow)).wakeMinutes
        return ReportFormat.clock(services.notifications.settings.morningCustomMinutes ?? wake)
    }
}
