import Foundation
import Observation
import Core
import Persistence
import Hydration
import Insights

@MainActor
@Observable
public final class StatsViewModel {
    private let services: AppServices

    public var chartMode: VolumeChartMode = .days7
    public var period: StatsPeriod = .week7
    public var monthOffset = 0
    public var selectedDay: DayKey?
    public var showCalculator = false
    public var showTypicalInfo = false

    // Стан калькулятора норми
    public var weightKg: Double = 70
    public var activity: ActivityLevel = .medium
    public var climate: ClimateLevel = .moderate

    public init(services: AppServices) {
        self.services = services
        if let weight = services.profile.weightKg { weightKg = weight }
        activity = services.profile.activity
        climate = services.profile.climate
    }

    // MARK: - Звіти

    public var evenness: EvennessReport { services.insights.evenness() }
    public var volumeChart: VolumeChartReport { services.insights.volumeChart(mode: chartMode) }
    public var typicalDay: TypicalDayReport { services.insights.typicalDay(period: period) }
    public var heatmap: HeatmapReport { services.insights.heatmap(period: period) }

    public var month: MonthKey {
        services.calendar.monthKey(offsetMonths: monthOffset, from: services.calendar.currentMonth)
    }

    public var calendarReport: CalendarMonthReport { services.insights.calendar(month: month) }

    public var dayDetail: DayDetailReport? {
        guard let selectedDay else { return nil }
        return services.insights.dayDetail(for: selectedDay)
    }

    public var goalLabel: String {
        let goal = chartMode == .days7 ? services.hydration.currentGoal() : services.hydration.currentGoal() * 7
        return "\(Volume.litersLabel(goal, fractionDigits: 1)) л"
    }

    // MARK: - Дії

    public func shiftMonth(_ delta: Int) {
        let candidate = monthOffset + delta
        guard candidate <= 0 else { return }
        let report = services.insights.calendar(
            month: services.calendar.monthKey(offsetMonths: candidate, from: services.calendar.currentMonth)
        )
        // Далі за місяць встановлення не гортаємо.
        if delta < 0, !calendarReport.canGoBack, !report.hasData { return }
        monthOffset = candidate
        selectedDay = nil
    }

    public func select(day: DayKey?) {
        selectedDay = selectedDay == day ? nil : day
    }

    public func stepWeight(_ delta: Double) {
        weightKg = max(35, min(160, weightKg + delta))
    }

    public var calculatedGoal: Int {
        services.hydration.calculateGoal(
            inputs: GoalInputs(
                weightKg: weightKg,
                gender: services.profile.gender,
                birthYear: services.profile.birthYear,
                activity: activity,
                climate: climate
            )
        )
    }

    public func applyCalculatedGoal() {
        let profile = services.profile
        profile.weightKg = weightKg
        profile.activity = activity
        profile.climate = climate
        services.profiles.save()
        services.hydration.setGoal(calculatedGoal, source: .calculated)
        services.touch()
        showCalculator = false
    }
}
