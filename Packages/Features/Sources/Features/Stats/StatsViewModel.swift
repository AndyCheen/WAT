import Foundation
import DesignSystem
import SwiftUI
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


    // MARK: - Анімовані переходи

    /// Прапорці шторок присвоювались напряму, тому переходи `WTSheet`/`WTModal`
    /// ніколи не програвались. Тепер будь-яка зміна йде через пружину дизайн-системи.
    public func present(_ flag: ReferenceWritableKeyPath<StatsViewModel, Bool>) {
        withAnimation(WTAnimation.sheet) { self[keyPath: flag] = true }
    }

    public func dismiss(_ flag: ReferenceWritableKeyPath<StatsViewModel, Bool>) {
        withAnimation(WTAnimation.sheet) { self[keyPath: flag] = false }
    }
    // MARK: - Звіти

    /// Звіти рахуються на льоту в `body`, тож читання `epoch` тут підписує екран на нову
    /// добу й повернення з фону — окремий `reload()` не потрібен.
    private var insights: InsightsService {
        _ = services.epoch
        return services.insights
    }

    public var evenness: EvennessReport { insights.evenness() }
    public var volumeChart: VolumeChartReport { insights.volumeChart(mode: chartMode) }
    public var typicalDay: TypicalDayReport { insights.typicalDay(period: period) }
    public var heatmap: HeatmapReport { insights.heatmap(period: period) }

    public var month: MonthKey {
        services.calendar.monthKey(offsetMonths: monthOffset, from: services.calendar.currentMonth)
    }

    public var calendarReport: CalendarMonthReport { insights.calendar(month: month) }

    public var dayDetail: DayDetailReport? {
        guard let selectedDay else { return nil }
        return insights.dayDetail(for: selectedDay)
    }

    /// Звіти-історії з 4a (WAT-67): раніше їх відкривало лише сповіщення — хто без дозволу чи змахнув, звіту не бачив.
    /// Лише періоди з порціями: порожня історія нічого не розповість.
    public struct ReportLink: Identifiable, Equatable {
        public let title: String
        public let period: ReportPeriod
        public var id: String { period.encoded }
    }

    public var reportLinks: [ReportLink] {
        _ = services.epoch
        let calendar = services.calendar
        let today = calendar.today
        let candidates = [
            ReportLink(title: "Вчора", period: .day(calendar.dayKey(offsetDays: -1, from: today))),
            ReportLink(title: "Минулий тиждень", period: calendar.period(.week, containing: calendar.dayKey(offsetDays: -7, from: today))),
            ReportLink(title: "Минулий місяць", period: .month(calendar.monthKey(offsetMonths: -1, from: calendar.currentMonth)))
        ]
        return candidates.filter { link in
            let days = calendar.days(in: link.period)
            guard let first = days.first, let last = days.last else { return false }
            return services.dayLogs.dayLogs(from: first, to: last).contains { $0.totalMl > 0 }
        }
    }

    public var goalLabel: String {
        let goal = chartMode == .weeks8 ? services.hydration.currentGoal() * 7 : services.hydration.currentGoal()
        let label = volumeUnit.format(goal) { "\(Volume.litersLabel($0, fractionDigits: 1)) л" }
        // Рік — середнє за активний день місяця, тож і ціль — денна.
        return chartMode == .months12 ? label + " на день" : label
    }

    /// Система об'єму людини (WAT-46).
    public var volumeUnit: VolumeUnit { services.profile.volumeUnit }
    public var massUnit: MassUnit { services.profile.massUnit }
    /// Години блоків «Рівномірності» — у форматі людини (WAT-58).
    public var timeFormat: TimeFormat { services.profile.timeFormat }

    // MARK: - Дії

    public func shiftMonth(_ delta: Int) {
        let candidate = monthOffset + delta
        guard candidate <= 0 else { return }
        let report = insights.calendar(
            month: services.calendar.monthKey(offsetMonths: candidate, from: services.calendar.currentMonth)
        )
        // Далі за місяць встановлення не гортаємо.
        if delta < 0, !calendarReport.canGoBack, !report.hasData { return }
        monthOffset = candidate
        selectedDay = nil
    }

    public func select(day: DayKey?) {
        selectedDay = selectedDay == day ? nil : day
        if let selectedDay, selectedDay < services.calendar.today { services.record(.pastDayOpened) }
    }

    /// Крок — одиниця людини: кілограм чи фунт. Від показаного числа, а не від кілограмів: інакше
    /// «154 фунти» − 1 могли б знову показати 154 (WAT-58). Межі — 35…160 кг, як і були.
    public func stepWeight(_ delta: Int) {
        let shown = massUnit.units(weightKg) + delta
        weightKg = max(35, min(160, Mass.kilograms(shown, from: massUnit)))
    }

    /// «70 кг» / «154 фунти».
    public var weightLabel: String { massUnit.label(weightKg) }

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
