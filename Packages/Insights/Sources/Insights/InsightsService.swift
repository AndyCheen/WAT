import Foundation
import Core
import Persistence
import Metrics

/// Постачає готові до рендера звіти для екрана 4a та шторки статистики 1a.
@MainActor
public final class InsightsService {
    private let dayLogs: DayLogRepositoryProtocol
    private let profiles: ProfileRepositoryProtocol
    private let metrics: MetricsService
    private let calendar: CalendarService

    public init(
        dayLogs: DayLogRepositoryProtocol,
        profiles: ProfileRepositoryProtocol,
        metrics: MetricsService,
        calendar: CalendarService
    ) {
        self.dayLogs = dayLogs
        self.profiles = profiles
        self.metrics = metrics
        self.calendar = calendar
    }

    // MARK: - Рівномірність за день

    public func evenness(for day: DayKey? = nil) -> EvennessReport {
        let key = day ?? calendar.today
        let goal = profiles.currentGoalMl(on: key)
        guard let log = dayLogs.existingDayLog(for: key) else {
            return EvennessReport(
                score: 0,
                rows: InsightsCalculators.evennessRows(partTotals: [0, 0, 0, 0, 0], goalMl: goal),
                totalMl: 0
            )
        }
        return EvennessReport(
            score: InsightsCalculators.evennessScore(partTotals: log.partTotals),
            rows: InsightsCalculators.evennessRows(partTotals: log.partTotals, goalMl: log.goalMlSnapshot),
            totalMl: log.totalMl
        )
    }

    // MARK: - Обʼєм по днях / тижнях

    public func volumeChart(mode: VolumeChartMode) -> VolumeChartReport {
        switch mode {
        case .days7: return dailyVolumeChart(days: 7)
        case .weeks8: return weeklyVolumeChart(weeks: 8)
        }
    }

    private func dailyVolumeChart(days: Int) -> VolumeChartReport {
        let keys = calendar.recentDays(days)
        let logs = Dictionary(
            uniqueKeysWithValues: dayLogs.dayLogs(from: keys.first!, to: keys.last!).map { ($0.dayKey, $0) }
        )
        let goal = profiles.currentGoalMl(on: calendar.today)

        let bars = keys.map { key -> VolumeBar in
            let log = logs[key.rawValue]
            let weekday = calendar.calendar.component(.weekday, from: calendar.date(from: key))
            let index = (weekday - calendar.calendar.firstWeekday + 7) % 7
            return VolumeBar(
                label: CalendarService.weekdayLabels[index],
                ml: log?.totalMl ?? 0,
                goalMl: log?.goalMlSnapshot ?? goal,
                key: key.rawValue
            )
        }
        return VolumeChartReport(
            bars: bars,
            goalMl: goal,
            maxValue: max(bars.map(\.ml).max() ?? 0, goal)
        )
    }

    private func weeklyVolumeChart(weeks: Int) -> VolumeChartReport {
        let allKeys = calendar.recentDays(weeks * 7)
        guard let first = allKeys.first, let last = allKeys.last else { return .empty }
        let logs = Dictionary(
            uniqueKeysWithValues: dayLogs.dayLogs(from: first, to: last).map { ($0.dayKey, $0) }
        )
        let goal = profiles.currentGoalMl(on: calendar.today)
        let weeklyGoal = goal * 7

        let bars = (0..<weeks).map { index -> VolumeBar in
            let slice = allKeys[(index * 7)..<((index + 1) * 7)]
            let total = slice.reduce(0) { $0 + (logs[$1.rawValue]?.totalMl ?? 0) }
            return VolumeBar(label: "Т\(index + 1)", ml: total, goalMl: weeklyGoal, key: "w\(index)")
        }
        return VolumeChartReport(
            bars: bars,
            goalMl: weeklyGoal,
            maxValue: max(bars.map(\.ml).max() ?? 0, weeklyGoal)
        )
    }

    // MARK: - Календар-теплокарта

    public func calendar(month: MonthKey) -> CalendarMonthReport {
        let logs = Dictionary(
            uniqueKeysWithValues: dayLogs.dayLogs(in: month).map { ($0.dayKey, $0) }
        )
        let blanks = calendar.leadingBlanks(in: month)
        let total = calendar.numberOfDays(in: month)

        var days: [CalendarDay] = (0..<blanks).map { CalendarDay.blank(index: $0) }
        for number in 1...total {
            let key = DayKey(rawValue: String(format: "%@-%02d", month.rawValue, number))
            let log = logs[key.rawValue]
            days.append(
                CalendarDay(
                    dayKey: key,
                    number: number,
                    completionPct: log?.completionPct ?? 0,
                    goalMet: log?.goalMet ?? false,
                    isToday: calendar.isToday(key),
                    isFuture: calendar.isFuture(key),
                    hasData: log != nil
                )
            )
        }

        let earliest = dayLogs.earliestDayKey().map { MonthKey(rawValue: String($0.rawValue.prefix(7))) }
        return CalendarMonthReport(
            month: month,
            title: calendar.monthTitle(month),
            days: days,
            hasData: !logs.isEmpty,
            canGoBack: earliest.map { month > $0 } ?? false,
            canGoForward: month < calendar.currentMonth
        )
    }

    // MARK: - Деталі дня

    public func dayDetail(for day: DayKey) -> DayDetailReport? {
        guard let log = dayLogs.existingDayLog(for: day) else { return nil }
        let formatter = Self.timeFormatter(calendar)
        let entries = dayLogs.activeIntakes(for: day).map {
            DayDetailReport.Entry(
                id: $0.id, amountMl: $0.amountMl, timeLabel: formatter.string(from: $0.createdAt)
            )
        }
        let monthIndex = max(1, min(12, day.month)) - 1
        return DayDetailReport(
            dayKey: day,
            title: "\(day.day) \(CalendarService.monthNamesGenitive[monthIndex])",
            totalMl: log.totalMl,
            goalMl: log.goalMlSnapshot,
            completionPct: log.completionPct,
            rhythm: InsightsCalculators.evennessRows(partTotals: log.partTotals, goalMl: log.goalMlSnapshot),
            entries: entries
        )
    }

    // MARK: - Типова доба

    public func typicalDay(period: StatsPeriod) -> TypicalDayReport {
        let keys = calendar.recentDays(period.days)
        guard let first = keys.first, let last = keys.last else { return .empty }
        let totals = dayLogs.dayLogs(from: first, to: last).map(\.partTotals)
        return InsightsCalculators.typicalDay(dailyPartTotals: totals)
    }

    // MARK: - Теплокарта «Коли ти пʼєш»

    public func heatmap(period: StatsPeriod) -> HeatmapReport {
        let keys = calendar.recentDays(period.days)
        let hours = InsightsCalculators.heatmapHours
        var matrix = Array(repeating: Array(repeating: 0, count: hours.count), count: 7)
        var daysWithData = Set<String>()

        for key in keys {
            for event in metrics.events(.intakeAdded, day: key) {
                guard let bucket = InsightsCalculators.bucketIndex(forHour: event.hourBucket) else { continue }
                let weekday = calendar.calendar.component(.weekday, from: calendar.date(from: key))
                let row = (weekday - calendar.calendar.firstWeekday + 7) % 7
                matrix[row][bucket] += Int(event.value)
                daysWithData.insert(key.rawValue)
            }
        }

        let maxValue = matrix.flatMap { $0 }.max() ?? 0
        let rows = matrix.enumerated().map { rowIndex, cells in
            cells.enumerated().map { columnIndex, ml in
                HeatmapCell(
                    weekdayIndex: rowIndex,
                    hourBucket: hours[columnIndex],
                    ml: ml,
                    level: InsightsCalculators.heatmapLevel(ml: ml, maxMl: maxValue)
                )
            }
        }

        let subtitle = period == .week7
            ? "Останні 7 днів"
            : "Середнє за 30 днів · враховано \(daysWithData.count) днів із 30"

        return HeatmapReport(
            hours: hours, rows: rows, subtitle: subtitle, daysCounted: daysWithData.count
        )
    }

    // MARK: - Тиждень для шторки 1a

    public func weekSummary() -> WeekSummary {
        let chart = dailyVolumeChart(days: 7)
        let values = chart.bars.map(\.ml)
        guard !values.isEmpty else { return .empty }
        return WeekSummary(
            bars: chart.bars,
            averageMl: values.reduce(0, +) / values.count,
            bestMl: values.max() ?? 0,
            totalMl: values.reduce(0, +)
        )
    }

    private static func timeFormatter(_ calendar: CalendarService) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = calendar.calendar.timeZone
        return f
    }
}
