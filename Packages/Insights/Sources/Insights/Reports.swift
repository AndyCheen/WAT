import Foundation
import Core
import Persistence

// Звіти за день / тиждень / місяць — SPEC-NOTIFICATIONS §11. Не зберігаються: рахуються з `DayLog`
// на льоту (§11.3). Тут лише числа й думка звіту; тексти складає `Features` (слайди) і
// `Notifications` (сповіщення), щоб кожен модуль формулював своє.

/// Один день періоду.
public struct ReportDay: Equatable, Sendable {
    public let day: DayKey
    /// Фактично випито (`DayLog.totalMl`) — це звіт про воду, а не про зараховане до стелі.
    public let totalMl: Int
    public let goalMl: Int
    public let goalMet: Bool
    public let entries: Int
    /// День ще не настав — у тижні, що триває, або в поточному місяці.
    public let isFuture: Bool

    public var hasData: Bool { entries > 0 }
    public var fraction: Double { goalMl > 0 ? Double(totalMl) / Double(goalMl) : 0 }
}

/// Ціль частини доби в звіті (§9): та сама, за яку чекпоінт і +10 XP.
public struct ReportBlock: Equatable, Sendable {
    public let parts: [DayPart]
    public let title: String
    public let fromMinute: Int
    public let toMinute: Int
    public let targetMl: Int
    /// Денний звіт — скільки випито в межах частини; для тижня й місяця — `nil`.
    public let drunkMl: Int?
    /// Від потрібного: день — факт, тиждень і місяць — медіана активних днів.
    public let ratio: Double
    /// Медіана попереднього періоду — для «вечір підтягнувся на 12 %».
    public let previousRatio: Double?

    public var deadlinePart: DayPart { parts[parts.count - 1] }
    public var key: String { deadlinePart.key }
    public var isReached: Bool { ratio >= 1 }
}

/// Кілька днів поспіль із закритою нормою.
public struct StreakRun: Equatable, Sendable {
    public let start: DayKey
    public let end: DayKey
    public let length: Int
}

/// Попередній період того самого виду — для динаміки (§11.3, блок 5).
public struct ReportComparison: Equatable, Sendable {
    public let averageMl: Int
    public let goalDays: Int
    public let longestStreak: Int
}

/// Системна прогалина (§10.1): частина доби, яку людина стабільно недобирає.
public struct WeakPart: Equatable, Sendable {
    public let title: String
    public let key: String
    /// Медіана частки від потрібного.
    public let median: Double
    /// Кінець частини — для поради «одна склянка до 17:00».
    public let toMinute: Int
}

/// Одна думка звіту — перше правило §11.4, що спрацювало.
public enum ReportThought: Equatable, Sendable {
    /// 1. Системна прогалина: «Вечір — найслабше місце: у середньому 40 % від потрібного».
    case weakPart(WeakPart)
    /// 2. Покращення ≥ 10 % проти попереднього періоду.
    case improvement(percent: Int)
    /// 3. Рекорд: найдовша серія за весь час.
    case recordStreak(days: Int)
    /// 4. Будні проти вихідних, різниця ≥ 25 %.
    case weekendGap(percent: Int, weekendLess: Bool)
    /// 5. Інакше — найкращий день.
    case bestDay(ReportDay)
    /// Денний звіт: правила про тиждень і рекорди на одному дні сенсу не мають (рішення від 05.10.2026).
    case strongestPart(title: String, percent: Int)
}

public struct PeriodReport: Equatable, Sendable {
    public let period: ReportPeriod
    /// Усі дні періоду, від першого до останнього, разом із майбутніми.
    public let days: [ReportDay]
    public let totalMl: Int
    public let goalDays: Int
    /// Середнє на день — за дні, що вже настали.
    public let averageMl: Int
    /// Норма дня (денний звіт) або поточна норма.
    public let goalMl: Int
    public let glassMl: Int
    /// Порції дня в хвилинах доби — для слайда «як минув день».
    public let portions: [TimedPortion]
    /// Порожньо в режимі «просто норма» (WAT-42, §28): звіт тоді не судить частини доби.
    public let blocks: [ReportBlock]
    /// Розклад, з якого побудовано `blocks` — першого дня періоду, зі знімка його запису.
    public let schedule: DaySchedule
    public let previous: ReportComparison?
    public let longestStreak: StreakRun?
    public let weekdayAverageMl: Int?
    public let weekendAverageMl: Int?
    public let thought: ReportThought?

    public var elapsedDays: [ReportDay] { days.filter { !$0.isFuture } }
    /// Звіт із цілями частин доби — увімкнено «Ритм дня».
    public var showsDayParts: Bool { !blocks.isEmpty }
    public var hasData: Bool { days.contains(where: \.hasData) }
    public var bestDay: ReportDay? { elapsedDays.filter(\.hasData).max { $0.totalMl < $1.totalMl } }
    public var glasses: Int { glassMl > 0 ? Int((Double(totalMl) / Double(glassMl)).rounded()) : 0 }
    /// Зміна середнього проти попереднього періоду, %; `nil` — порівнювати нема з чим.
    public var averageChangePercent: Int? {
        guard let previous, previous.averageMl > 0, averageMl > 0 else { return nil }
        return Int((Double(averageMl - previous.averageMl) / Double(previous.averageMl) * 100).rounded())
    }
    public var strongestBlock: ReportBlock? {
        blocks.filter { $0.ratio > 0 }.max { $0.ratio < $1.ratio }
    }
    public var weakestBlock: ReportBlock? {
        blocks.filter { !$0.isReached }.min { $0.ratio < $1.ratio }
    }
}

/// Пороги звіту (§10.1, §11.4) — в одному місці, як `NotificationRules`.
public enum ReportRules {
    public static let weakMinActiveDays = 7
    public static let weakMedian = 0.5
    public static let weakUpperQuartile = 0.8
    public static let improvementPercent = 10
    public static let weekendGapPercent = 25
    public static let recordMinStreak = 3
}

extension InsightsService {
    // MARK: - Звіт за період

    /// `withThought: false` — для тексту сповіщення: думка там не потрібна, а правило «рекорд»
    /// читає всю історію, а контекст планувальника збирається на кожне перепланування.
    ///
    /// Режим «просто норма» (WAT-42, §28) — за поточним перемикачем, а не за днем звіту: звіт не
    /// зберігається, а частини доби людина бачити не хоче, хоч би за який період дивилась.
    public func report(for period: ReportPeriod, withThought: Bool = true) -> PeriodReport {
        let snapshot = periodSnapshot(period)
        let previous = periodSnapshot(calendar.shifted(period, by: -1))
        let profile = profiles.profile()

        let curve = templateCurve(for: period)
        let goalBlocks = profile.dayRhythmEnabled ? curve.goalBlocks() : []
        let blocks: [ReportBlock] = goalBlocks.map { block in
            let ratios = snapshot.blockRatios[block.deadlinePart.key] ?? []
            let previousRatios = previous.blockRatios[block.deadlinePart.key] ?? []
            let drunk: Int? = period.kind == .day ? block.drunkMl(of: snapshot.portions) : nil
            let ratio: Double
            if let drunk {
                ratio = block.targetMl > 0 ? Double(drunk) / Double(block.targetMl) : 0
            } else {
                ratio = InsightsCalculators.percentile(ratios.sorted(), 0.5)
            }
            return ReportBlock(
                parts: block.parts, title: block.title, fromMinute: block.fromMinute, toMinute: block.toMinute,
                targetMl: block.targetMl, drunkMl: drunk, ratio: ratio,
                previousRatio: previousRatios.isEmpty ? nil : InsightsCalculators.percentile(previousRatios.sorted(), 0.5)
            )
        }

        let comparison = previous.elapsed.isEmpty ? nil : ReportComparison(
            averageMl: previous.averageMl, goalDays: previous.goalDays, longestStreak: previous.longestRun?.length ?? 0
        )
        let active = snapshot.elapsed.filter(\.hasData)
        let weekdays = active.filter { !calendar.isWeekend($0.day) }
        let weekends = active.filter { calendar.isWeekend($0.day) }
        let average: ([ReportDay]) -> Int? = { $0.count >= 2 ? $0.reduce(0) { $0 + $1.totalMl } / $0.count : nil }

        var report = PeriodReport(
            period: period, days: snapshot.days, totalMl: snapshot.totalMl, goalDays: snapshot.goalDays,
            averageMl: snapshot.averageMl, goalMl: snapshot.days.last?.goalMl ?? profiles.currentGoalMl(on: calendar.today),
            glassMl: profile.glassMl, portions: snapshot.portions, blocks: blocks,
            schedule: DaySchedule(wakeMinutes: curve.wakeMinutes, sleepMinutes: curve.sleepMinutes), previous: comparison,
            longestStreak: snapshot.longestRun, weekdayAverageMl: average(weekdays), weekendAverageMl: average(weekends),
            thought: nil
        )
        if withThought { report = report.with(thought: thought(for: report)) }
        return report
    }

    /// Системна прогалина за §10.1: щонайменше 7 днів із порціями; частина доби — прогалина,
    /// якщо медіана частки від потрібного < 0,5 і верхній квартиль < 0,8 (квартиль відсіює
    /// частину, яку «то закриває, то ні»). З кількох — та, де медіана найменша.
    ///
    /// Частини — блоки цілей (`GoalBlock`), а не сирі `DayPart`: обрізаний активними годинами
    /// «ранок» 08–09 мав би ціль 138 мл і випадкові 300 % через одну склянку.
    public func weakDayPart(days: [DayKey]) -> WeakPart? {
        guard let first = days.first, let last = days.last else { return nil }
        let logs = dayLogs.dayLogs(from: first, to: last).filter { $0.entriesCount > 0 }
        guard logs.count >= ReportRules.weakMinActiveDays else { return nil }

        var ratios: [String: [Double]] = [:]
        var meta: [String: GoalBlock] = [:]
        for log in logs {
            let day = DayKey(rawValue: log.dayKey)
            for (block, ratio) in blockRatios(log: log, day: day) {
                ratios[block.deadlinePart.key, default: []].append(ratio)
                meta[block.deadlinePart.key] = meta[block.deadlinePart.key] ?? block
            }
        }
        return ratios.compactMap { key, values -> WeakPart? in
            let sorted = values.sorted()
            let median = InsightsCalculators.percentile(sorted, 0.5)
            let upper = InsightsCalculators.percentile(sorted, 0.75)
            guard median < ReportRules.weakMedian, upper < ReportRules.weakUpperQuartile, let block = meta[key] else { return nil }
            return WeakPart(title: block.title, key: key, median: median, toMinute: block.toMinute)
        }
        .min { $0.median < $1.median }
    }

    // MARK: - Внутрішнє

    private struct Snapshot {
        var days: [ReportDay] = []
        var portions: [TimedPortion] = []
        var blockRatios: [String: [Double]] = [:]
        var elapsed: [ReportDay] { days.filter { !$0.isFuture } }
        var totalMl: Int { days.reduce(0) { $0 + $1.totalMl } }
        var goalDays: Int { days.filter(\.goalMet).count }
        var averageMl: Int { elapsed.isEmpty ? 0 : totalMl / elapsed.count }
        var longestRun: StreakRun? { InsightsService.longestRun(in: elapsed) }
    }

    private func periodSnapshot(_ period: ReportPeriod) -> Snapshot {
        let keys = calendar.days(in: period)
        guard let first = keys.first, let last = keys.last else { return Snapshot() }
        let logs = Dictionary(dayLogs.dayLogs(from: first, to: last).map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        let today = calendar.today

        var snapshot = Snapshot()
        for key in keys {
            let log = logs[key.rawValue]
            snapshot.days.append(ReportDay(
                day: key, totalMl: log?.totalMl ?? 0,
                goalMl: log?.goalMlSnapshot ?? profiles.currentGoalMl(on: key),
                goalMet: log?.goalMet ?? false, entries: log?.entriesCount ?? 0, isFuture: key > today
            ))
            guard let log, log.entriesCount > 0 else { continue }
            for (block, ratio) in blockRatios(log: log, day: key) {
                snapshot.blockRatios[block.deadlinePart.key, default: []].append(ratio)
            }
            if period.kind == .day { snapshot.portions = portions(of: log) }
        }
        return snapshot
    }

    /// Крива, з якої беруться блоки звіту: перший день періоду, його знімки розкладу й норми.
    /// Розклад вихідних чи змінений підйом може дати іншим дням інші межі — тоді частини
    /// зводяться за ключем кінцевої частини.
    private func templateCurve(for period: ReportPeriod) -> PaceCurve {
        let day = calendar.days(in: period).first ?? calendar.today
        return dayCurve(dayLogs.existingDayLog(for: day), day: day, profile: profiles.profile())
    }

    /// Кожен день — зі своїм розкладом (WAT-39): звіт за вересень після зміни підйому в жовтні
    /// оцінює вересневі частини доби так само, як XP, нарахований тоді.
    private func blockRatios(log: DayLog, day: DayKey) -> [(GoalBlock, Double)] {
        let portions = portions(of: log)
        return dayCurve(log, day: day, profile: profiles.profile()).goalBlocks().map { block in
            (block, block.targetMl > 0 ? Double(block.drunkMl(of: portions)) / Double(block.targetMl) : 0)
        }
    }

    private func portions(of log: DayLog) -> [TimedPortion] {
        (log.intakes ?? []).filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }.map { intake in
            let parts = calendar.calendar.dateComponents([.hour, .minute], from: intake.createdAt)
            return TimedPortion(minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), ml: intake.amountMl)
        }
    }

    nonisolated static func longestRun(in days: [ReportDay]) -> StreakRun? {
        var best: StreakRun?
        var start: DayKey?
        var length = 0
        for day in days {
            if day.goalMet {
                if length == 0 { start = day.day }
                length += 1
                if length > (best?.length ?? 0), let start {
                    best = StreakRun(start: start, end: day.day, length: length)
                }
            } else {
                length = 0
            }
        }
        return best
    }

    /// Найдовша серія за весь час — для правила «рекорд» (§11.4, п. 3). Лише на екрані звіту, не
    /// на шляху порції: читає всю історію.
    private func allTimeLongestStreak() -> Int {
        let logs = dayLogs.allDayLogs().sorted { $0.dayKey < $1.dayKey }
        var best = 0, run = 0
        var previous: DayKey?
        for log in logs {
            let day = DayKey(rawValue: log.dayKey)
            let consecutive = previous.map { calendar.daysBetween($0, day) == 1 } ?? false
            if log.goalMet {
                run = consecutive ? run + 1 : 1
                best = max(best, run)
            } else {
                run = 0
            }
            previous = day
        }
        return best
    }

    private func thought(for report: PeriodReport) -> ReportThought? {
        guard report.hasData else { return nil }
        if report.period.kind == .day {
            // Без ритму дня думки дня немає — слайд бере загальну фразу (WAT-42).
            guard let strongest = report.strongestBlock else { return nil }
            return .strongestPart(title: strongest.title, percent: Int((strongest.ratio * 100).rounded()))
        }

        // 1. Системна прогалина — за 14 днів, що закінчуються останнім днем періоду (§10.1).
        // У режимі «просто норма» не береться: це порада про частину доби (WAT-42).
        let days = calendar.days(in: report.period)
        let end = min(days.last ?? calendar.today, calendar.today)
        let window = report.period.kind == .week ? calendar.recentDays(14, endingAt: end) : days.filter { $0 <= end }
        if report.showsDayParts, let weak = weakDayPart(days: window) { return .weakPart(weak) }

        // 2. Покращення ≥ 10 %.
        if let change = report.averageChangePercent, change >= ReportRules.improvementPercent {
            return .improvement(percent: change)
        }

        // 3. Рекорд — лише коли до періоду вже була історія: інакше перший тиждень завжди «рекордний».
        if let run = report.longestStreak, run.length >= ReportRules.recordMinStreak,
           let earliest = dayLogs.earliestDayKey(), let first = days.first, earliest < first,
           run.length >= allTimeLongestStreak() {
            return .recordStreak(days: run.length)
        }

        // 4. Будні проти вихідних.
        if let weekday = report.weekdayAverageMl, let weekend = report.weekendAverageMl, weekday > 0 {
            let gap = Int((Double(weekday - weekend) / Double(weekday) * 100).rounded())
            if abs(gap) >= ReportRules.weekendGapPercent { return .weekendGap(percent: abs(gap), weekendLess: gap > 0) }
        }

        // 5. Найкращий день.
        return report.bestDay.map { .bestDay($0) }
    }
}

extension PeriodReport {
    func with(thought: ReportThought?) -> PeriodReport {
        PeriodReport(
            period: period, days: days, totalMl: totalMl, goalDays: goalDays, averageMl: averageMl, goalMl: goalMl,
            glassMl: glassMl, portions: portions, blocks: blocks, schedule: schedule, previous: previous, longestStreak: longestStreak,
            weekdayAverageMl: weekdayAverageMl, weekendAverageMl: weekendAverageMl, thought: thought
        )
    }
}
