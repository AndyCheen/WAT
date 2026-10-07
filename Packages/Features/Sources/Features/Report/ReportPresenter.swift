import Foundation
import Core
import Insights
import Gamification
import DesignSystem

/// Один слайд звіту-історії (SPEC-NOTIFICATIONS §11.3, макет Design/Notifications.html, кадри 4–6):
/// одна думка, одна картинка, одне-два речення. Тексти — тут, візуал — у `DesignSystem`.
enum ReportSlide {
    enum CoverVisual {
        case glass(fraction: Double)
        case drops(count: Int)
        case buckets([Double])
    }

    struct GoalRow: Equatable {
        let reached: Bool
        let title: String
        let value: String
    }

    struct Legend: Equatable {
        let caption: String
        let title: String
        let value: String
        let positive: Bool
    }

    struct Pill: Equatable {
        let text: String
        let positive: Bool
    }

    /// `unit` — «л» або «мл»: до літра обкладинка показує мілілітри, «0,3 л» читається гірше за «250 мл».
    case cover(kicker: String, value: Double, decimals: Int, unit: String, caption: String, visual: CoverVisual,
               pill: String?, foot: String?, waveLevel: Double)
    case timeline(kicker: String, title: String, blocks: [WTDayTimeline.Block], drops: [Double],
                  ticks: [(position: Double, label: String)], rows: [GoalRow], foot: String?)
    case weekGoals(kicker: String, goalDays: Int, dayCount: Int, days: [(label: String, met: Bool)],
                   pill: Pill?, foot: String?)
    case bestDay(kicker: String, title: String, subtitle: String, bars: [WTStoryBars.Bar], goalFraction: Double,
                 goalLabel: String, pill: Pill?)
    case rhythm(kicker: String, title: String, segments: [WTDayArc.Segment], markIndex: Int?, start: String,
                end: String, legend: [Legend], foot: String?)
    case mosaic(kicker: String, headline: String, leadingBlanks: Int, cells: [WTMonthMosaic.Cell], pill: Pill?)
    case streak(kicker: String, value: Int, caption: String, chain: [String], badges: [String], foot: String?)
    case game(xp: Int, level: String, fraction: Double, badges: [String], foot: String?)
    case thought(kicker: String, emoji: String, headline: String, detail: String?, versus: [WTVersusBars.Item])
    case empty(headline: String)

    var style: WTStoryStyle {
        switch self {
        case .cover, .streak, .game: return .water
        default: return .plain
        }
    }
}

/// Звіт → слайди. Чиста функція: усе потрібне приходить значеннями, тести — без UI.
struct ReportPresenter {
    let report: PeriodReport
    let game: GamificationPeriodSummary
    /// Поточна й найдовша серія — для денного звіту й «рекорду» місяця.
    let streak: StreakSummary
    /// Норма закрита в останні 7 днів, що закінчуються днем звіту, — ланцюжок денного слайда.
    let recentGoalDays: [Bool]
    let schedule: DaySchedule
    let weekendScheduleEnabled: Bool
    let dayPartXp: Int
    let today: DayKey
    /// «Завтра ранкова склянка — о 08:00» — лише в денному звіті за сьогодні.
    let tomorrowMorning: String?
    /// Хвилина доби зараз — у денному звіті за сьогодні частини, що ще попереду, не судяться.
    let nowMinute: Int?
    let calendar: CalendarService
    /// Система об'єму людини (WAT-46); у мілілітрах звіт — як був.
    var unit: VolumeUnit = .milliliters

    // MARK: - Шапка й навігація

    var header: String {
        switch report.period {
        case .day(let day):
            return "\(day.day) \(ReportFormat.monthGenitive(day.month)) · \(ReportFormat.weekday(calendar.weekdayIndex(of: day)))"
                .uppercased()
        case .week(let start):
            let end = calendar.dayKey(offsetDays: 6, from: start)
            let text = start.month == end.month
                ? "\(start.day)–\(end.day) \(ReportFormat.monthGenitive(end.month))"
                : "\(start.day) \(ReportFormat.monthGenitive(start.month)) – \(end.day) \(ReportFormat.monthGenitive(end.month))"
            return text.uppercased()
        case .month(let month):
            return "\(ReportFormat.monthName(month.month)) \(month.year)".uppercased()
        }
    }

    var previousTitle: String {
        switch report.period {
        case .day(let day): return day == today ? "‹ Учора" : "‹ Попередній день"
        case .week: return "‹ Попередній тиждень"
        case .month(let month): return "‹ \(ReportFormat.monthName(calendar.monthKey(offsetMonths: -1, from: month).month))"
        }
    }

    // MARK: - Слайди

    var slides: [ReportSlide] {
        guard report.hasData else {
            return [.empty(headline: "За цей період записів немає")]
        }
        switch report.period.kind {
        case .day: return daySlides
        case .week: return weekSlides
        case .month: return monthSlides
        }
    }

    private var daySlides: [ReportSlide] {
        guard case .day(let day) = report.period else { return [] }
        var result: [ReportSlide] = [dayCover(day), report.showsDayParts ? dayTimeline : dayPortions]
        if streak.current > 0 {
            result.append(.streak(
                kicker: "Серія", value: streak.current,
                caption: "\(ReportFormat.daysWord(streak.current)) поспіль із закритою нормою",
                chain: recentGoalDays.map { $0 ? "✓" : "·" }, badges: gameBadges(compact: true),
                foot: report.days.first?.goalMet == true ? "Норму закрито — серія продовжується" : nil
            ))
        } else if let game = gameSlide {
            result.append(game)
        }
        result.append(thoughtSlide(kicker: "Думка дня", emoji: day == today ? "🌙" : "💡",
                                   extra: day == today ? tomorrowMorning.map { "Добраніч. Завтра ранкова склянка — о \($0)." } : nil))
        return result
    }

    private var weekSlides: [ReportSlide] {
        var result: [ReportSlide] = [
            .cover(kicker: "Твій тиждень", value: ReportFormat.big(report.totalMl, unit).value,
                   decimals: ReportFormat.big(report.totalMl, unit).decimals, unit: ReportFormat.big(report.totalMl, unit).unit,
                   caption: "води за \(ReportFormat.daysWord(report.elapsedDays.count, withNumber: true)) — це \(glassesText)",
                   visual: .drops(count: min(report.glasses, 63)), pill: nil, foot: nil, waveLevel: 0.48),
            weekGoals,
            bestDaySlide
        ]
        // Без ритму дня тиждень — це норма й середнє: їх уже несуть «Норма» й «Найкращий день» (WAT-42).
        if report.showsDayParts {
            result.append(rhythmSlide(kicker: "Ритм доби", foot: "Медіана за тиждень, у межах твоїх активних годин."))
        }
        if let game = gameSlide { result.append(game) }
        result.append(thoughtSlide(kicker: "Думка тижня", emoji: "💡", extra: nil))
        return result
    }

    private var monthSlides: [ReportSlide] {
        guard case .month(let month) = report.period else { return [] }
        let name = ReportFormat.monthName(month.month)
        let buckets = Double(report.totalMl) / 10_000
        var caption = "води — це \(glassesText)"
        if buckets >= 1 {
            let whole = Int(buckets)
            caption += ", або понад \(whole) \(Plural.uk(whole, one: "відро", few: "відра", many: "відер"))"
        }
        var result: [ReportSlide] = [
            .cover(kicker: "Твій \(name.lowercased())", value: ReportFormat.big(report.totalMl, unit).value,
                   decimals: ReportFormat.big(report.totalMl, unit).decimals, unit: ReportFormat.big(report.totalMl, unit).unit,
                   caption: caption,
                   visual: .buckets(bucketFractions(buckets)), pill: nil,
                   foot: "У середньому \(ReportFormat.volume(report.averageMl, unit)) на день", waveLevel: 0.7),
            mosaicSlide(month)
        ]
        if let run = report.longestStreak, run.length >= 2 {
            result.append(.streak(
                kicker: "Найдовша серія", value: run.length,
                caption: "\(ReportFormat.daysWord(run.length)) поспіль — з \(run.start.day) по \(run.end.day) \(ReportFormat.monthGenitive(run.end.month))",
                chain: chainLabels(run), badges: [], foot: recordFoot(run.length)
            ))
        }
        if report.showsDayParts {
            result.append(rhythmSlide(kicker: "Що змінилось", foot: "Медіана частини доби від потрібного."))
        }
        if let game = gameSlide { result.append(game) }
        result.append(thoughtSlide(kicker: "Думка місяця", emoji: "💡", extra: nil))
        return result
    }

    // MARK: - День

    private func dayCover(_ day: DayKey) -> ReportSlide {
        let big = ReportFormat.big(report.totalMl, unit)
        let goal = report.goalMl
        let percent = goal > 0 ? Int((Double(report.totalMl) / Double(goal) * 100).rounded()) : 0
        let left = goal - report.totalMl
        let pill: String
        if left <= 0 {
            pill = "Норму закрито 🎉"
        } else if day == today {
            pill = left <= report.glassMl ? "Ще одна склянка — і норму закрито" : "Ще \(ReportFormat.volume(left, unit)) — і норму закрито"
        } else {
            pill = left <= report.glassMl ? "Ще одна склянка — і була б норма" : "До норми бракувало \(ReportFormat.volume(left, unit))"
        }
        return .cover(kicker: day == today ? "Сьогодні" : "\(day.day) \(ReportFormat.monthGenitive(day.month))",
                      value: big.value, decimals: big.decimals, unit: big.unit,
                      caption: "з \(ReportFormat.volume(goal, unit)) — це \(percent) % норми",
                      visual: .glass(fraction: goal > 0 ? Double(report.totalMl) / Double(goal) : 0),
                      pill: pill, foot: nil, waveLevel: 0.62)
    }

    /// Частка шкали дня від підйому (0) до відбою (1).
    private func position(_ minute: Int) -> Double {
        let wake = Double(schedule.wakeMinutes), span = Double(max(1, schedule.sleepMinutes - schedule.wakeMinutes))
        return max(0, min(1, (Double(minute) - wake) / span))
    }

    private var dayTimeline: ReportSlide {
        let blocks = report.blocks.map { block in
            WTDayTimeline.Block(
                from: position(block.fromMinute), to: position(block.toMinute), reached: block.isReached,
                label: block.isReached ? "✓ +\(dayPartXp) XP" : "\(unit.units(block.drunkMl ?? 0)) / \(unit.units(block.targetMl))"
            )
        }
        // Порції до підйому й після відбою — на краях шкали: вони зараховані першій і останній
        // частині (WAT-39), і зникнути зі шкали, яка показує ✓ за них, не можуть.
        let drops = report.portions.map { position($0.minute) }
        var ticks = [(position: 0.0, label: ReportFormat.clock(schedule.wakeMinutes))]
        ticks += report.blocks.dropLast().map { (position($0.toMinute), ReportFormat.clock($0.toMinute)) }
        ticks.append((1, ReportFormat.clock(schedule.sleepMinutes)))

        let rows = report.blocks.map { block in
            ReportSlide.GoalRow(reached: block.isReached,
                                title: "\(ReportFormat.clock(block.fromMinute))–\(ReportFormat.clock(block.toMinute))",
                                value: "\(unit.units(block.drunkMl ?? 0)) / \(unit.units(block.targetMl)) \(unit.symbol)")
        }
        let portions = report.days.first?.entries ?? report.portions.count
        let reached = report.blocks.filter(\.isReached).count
        let portionsText = "\(portions) \(Plural.uk(portions, one: "порція", few: "порції", many: "порцій"))"
        let title: String
        switch reached {
        case 0: title = "\(portionsText) за день"
        case report.blocks.count: title = "\(portionsText) — і всі частини дня закрито"
        default: title = "\(portionsText) — і \(reached) з \(report.blocks.count) частин дня закрито"
        }
        let foot = weakestPassedBlock.map {
            "Найслабше — \($0.title): \(ReportFormat.percent($0.ratio)) % від потрібного"
        } ?? (nowMinute == nil ? "Усі частини дня — у темпі" : nil)
        return .timeline(kicker: "Як минув день", title: title, blocks: blocks, drops: drops, ticks: ticks, rows: rows, foot: foot)
    }

    /// Режим «просто норма» (WAT-42, §28): та сама шкала дня з порціями, але без частин і ✓ —
    /// скільки разів і коли пив, без оцінки.
    private var dayPortions: ReportSlide {
        let portions = report.portions
        let count = report.days.first?.entries ?? portions.count
        let ticks = [(position: 0.0, label: ReportFormat.clock(schedule.wakeMinutes)),
                     (position: 1.0, label: ReportFormat.clock(schedule.sleepMinutes))]
        var foot: String?
        if let first = portions.first, let last = portions.last {
            foot = portions.count == 1
                ? "О \(ReportFormat.clock(first.minute))."
                : "Перша — о \(ReportFormat.clock(first.minute)), остання — о \(ReportFormat.clock(last.minute)). "
                    + "У середньому \(ReportFormat.volume(report.totalMl / portions.count, unit)) за раз."
        }
        return .timeline(kicker: "Випито за день",
                         title: "\(count) \(Plural.uk(count, one: "порція", few: "порції", many: "порцій")) за день",
                         blocks: [], drops: portions.map { position($0.minute) }, ticks: ticks, rows: [], foot: foot)
    }

    /// Найслабша незакрита частина — серед тих, що вже минули: посеред сьогоднішнього дня
    /// вечір із 0 % ще не провал.
    private var weakestPassedBlock: ReportBlock? {
        report.blocks
            .filter { block in !block.isReached && (nowMinute.map { block.toMinute <= $0 } ?? true) }
            .min { $0.ratio < $1.ratio }
    }

    // MARK: - Тиждень

    private var weekGoals: ReportSlide {
        let days = report.days.map { (label: ReportFormat.weekdayShort(calendar.weekdayIndex(of: $0.day)), met: $0.goalMet) }
        var pill: ReportSlide.Pill?
        if let previous = report.previous {
            let delta = report.goalDays - previous.goalDays
            if delta != 0 {
                let days = ReportFormat.daysWord(abs(delta), withNumber: true)
                pill = .init(text: delta > 0 ? "▲ на \(days) більше, ніж минулого тижня" : "▼ на \(days) менше, ніж минулого тижня",
                             positive: delta > 0)
            }
        }
        let missed = report.elapsedDays.filter { !$0.goalMet }
        let foot: String
        switch missed.count {
        case 0: foot = "Жодного пропуску."
        case 1...3:
            let names = missed.map { ReportFormat.weekday(calendar.weekdayIndex(of: $0.day)) }
            let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " й " + names[names.count - 1]
            foot = list.prefix(1).uppercased() + list.dropFirst() + " — без норми."
        default: foot = "\(ReportFormat.daysWord(missed.count, withNumber: true)) без норми — є куди рости."
        }
        return .weekGoals(kicker: "Норма", goalDays: report.goalDays, dayCount: report.elapsedDays.count, days: days,
                          pill: pill, foot: foot)
    }

    private var bestDaySlide: ReportSlide {
        let best = report.bestDay
        let scale = Double(max(report.goalMl * 5 / 4, report.days.map(\.totalMl).max() ?? 0, 1))
        let bars = report.days.map { day in
            WTStoryBars.Bar(label: ReportFormat.weekdayShort(calendar.weekdayIndex(of: day.day)),
                            fraction: Double(day.totalMl) / scale, met: day.goalMet, isBest: day.day == best?.day)
        }
        let title = best.map { "\(ReportFormat.weekday(calendar.weekdayIndex(of: $0.day)).capitalizedFirst) — \(ReportFormat.volume($0.totalMl, unit))" }
            ?? "Найкращий день"
        return .bestDay(kicker: "Найкращий день", title: title,
                        subtitle: "У середньому \(ReportFormat.volume(report.averageMl, unit)) на день",
                        bars: bars, goalFraction: Double(report.goalMl) / scale,
                        goalLabel: "норма \(ReportFormat.volume(report.goalMl, unit))", pill: changePill(suffix: "проти минулого тижня"))
    }

    // MARK: - Місяць

    private func mosaicSlide(_ month: MonthKey) -> ReportSlide {
        let run = report.longestStreak
        let cells = report.days.map { day -> WTMonthMosaic.Cell in
            let state: WTMonthMosaic.CellState = day.isFuture ? .future : day.goalMet ? .met : day.hasData ? .partial : .empty
            let inRun = run.map { $0.length >= 2 && day.day >= $0.start && day.day <= $0.end } ?? false
            return WTMonthMosaic.Cell(label: "\(day.day.day)", state: state, highlighted: inRun)
        }
        var pill: ReportSlide.Pill?
        if let previous = report.previous {
            let delta = report.goalDays - previous.goalDays
            let previousName = ReportFormat.monthLocative(calendar.monthKey(offsetMonths: -1, from: month).month)
            if delta != 0 {
                let days = ReportFormat.daysWord(abs(delta), withNumber: true)
                pill = .init(text: delta > 0 ? "▲ на \(days) більше, ніж у \(previousName)" : "▼ на \(days) менше, ніж у \(previousName)",
                             positive: delta > 0)
            }
        }
        let headline = "\(ReportFormat.daysWord(report.goalDays, withNumber: true)) норми з \(report.elapsedDays.count)"
        return .mosaic(kicker: "Норма", headline: headline, leadingBlanks: calendar.leadingBlanks(in: month), cells: cells, pill: pill)
    }

    private func bucketFractions(_ buckets: Double) -> [Double] {
        let whole = min(Int(buckets), 7)
        var result = Array(repeating: 1.0, count: whole)
        let rest = buckets - Double(Int(buckets))
        if rest >= 0.05, whole < 8 { result.append(rest) }
        return result.isEmpty ? [buckets] : result
    }

    private func chainLabels(_ run: StreakRun) -> [String] {
        let days = (0..<run.length).map { calendar.dayKey(offsetDays: $0, from: run.start) }
        guard days.count > 9 else { return days.map { "\($0.day)" } }
        return days.prefix(4).map { "\($0.day)" } + ["…"] + days.suffix(4).map { "\($0.day)" }
    }

    private func recordFoot(_ length: Int) -> String {
        guard streak.longest > length else { return "Це рекорд за весь час" }
        let gap = streak.longest - length
        return "Рекорд — \(ReportFormat.daysWord(streak.longest, withNumber: true)). До нього — \(ReportFormat.daysWord(gap, withNumber: true))."
    }

    // MARK: - Ритм доби

    private func rhythmSlide(kicker: String, foot: String) -> ReportSlide {
        let blocks = report.blocks
        let segments = blocks.map { WTDayArc.Segment(title: $0.title.capitalizedFirst, ratio: $0.ratio) }
        let strongest = report.strongestBlock
        let weakest = report.weakestBlock.flatMap { $0.ratio < 0.9 ? $0 : nil }
        let markIndex = weakest.flatMap { weak in blocks.firstIndex { $0.key == weak.key } }

        var title: String
        var legend: [ReportSlide.Legend] = []
        if report.period.kind == .month, let change = biggestChange() {
            title = "\(change.block.title.capitalizedFirst): \(change.delta > 0 ? "+" : "−")\(abs(change.delta)) % проти \(previousMonthGenitive)"
            legend = blocks.compactMap { block -> ReportSlide.Legend? in
                guard let previous = block.previousRatio else { return nil }
                let delta = Int(((block.ratio - previous) * 100).rounded())
                guard delta != 0 else { return nil }
                return .init(caption: block.title.uppercased(), title: "\(ReportFormat.percent(block.ratio)) %",
                             value: "\(delta > 0 ? "▲" : "▼") \(abs(delta)) %", positive: delta > 0)
            }
            .sorted { $0.positive && !$1.positive }
            .prefix(2).map { $0 }
        } else if let strongest, let weakest, strongest.key != weakest.key {
            // Без дієслова: «ранок і полудень просідає» не узгоджувалось би з множиною.
            title = "\(strongest.title.capitalizedFirst) — твоя суперсила, найслабше — \(weakest.title)"
        } else {
            title = "Рівно весь день — частини доби в темпі"
        }
        if legend.isEmpty {
            if let strongest {
                legend.append(.init(caption: "НАЙСИЛЬНІША", title: strongest.title.capitalizedFirst,
                                    value: "\(ReportFormat.percent(strongest.ratio)) % від потрібного", positive: true))
            }
            if let weakest {
                legend.append(.init(caption: "НАЙСЛАБША", title: weakest.title.capitalizedFirst,
                                    value: "\(ReportFormat.percent(weakest.ratio)) % від потрібного", positive: false))
            }
        }
        return .rhythm(kicker: kicker, title: title, segments: segments, markIndex: markIndex,
                       start: ReportFormat.clock(schedule.wakeMinutes), end: ReportFormat.clock(schedule.sleepMinutes),
                       legend: legend, foot: foot)
    }

    private func biggestChange() -> (block: ReportBlock, delta: Int)? {
        report.blocks.compactMap { block -> (ReportBlock, Int)? in
            guard let previous = block.previousRatio else { return nil }
            return (block, Int(((block.ratio - previous) * 100).rounded()))
        }
        .filter { $0.1 != 0 }
        .max { abs($0.1) < abs($1.1) }
    }

    private var previousMonthGenitive: String {
        guard case .month(let month) = report.period else { return "минулого" }
        return ReportFormat.monthGenitive(calendar.monthKey(offsetMonths: -1, from: month).month)
    }

    // MARK: - Гра

    private var gameSlide: ReportSlide? {
        guard !game.isEmpty else { return nil }
        let level = game.newLevels > 1 ? "\(game.levelBefore)→\(game.levelAfter)" : "\(game.levelAfter)"
        return .game(xp: game.xp, level: level, fraction: game.fractionIntoLevel, badges: gameBadges(compact: false),
                     foot: game.xpToNextLevel > 0 ? "До рівня \(game.levelAfter + 1) — \(game.xpToNextLevel) XP" : nil)
    }

    private func gameBadges(compact: Bool) -> [String] {
        var badges: [String] = []
        if compact, game.xp > 0 { badges.append("+\(game.xp) XP") }
        if game.newLevels == 1 { badges.append("🎉 Новий рівень") }
        if game.newLevels > 1 { badges.append("🎉 \(game.newLevels) нові рівні") }
        if compact, game.achievements.count == 1, let first = game.achievements.first {
            badges.append("\(first.emoji) \(first.title)")
        } else if !game.achievements.isEmpty {
            let n = game.achievements.count
            badges.append("🏅 \(n) \(Plural.uk(n, one: "досягнення", few: "досягнення", many: "досягнень"))")
        }
        if !compact, game.questsCompleted > 0 {
            let n = game.questsCompleted
            badges.append("✓ \(n) \(Plural.uk(n, one: "завдання", few: "завдання", many: "завдань"))")
        }
        // Призи — лише в місячному звіті (SPEC-PRIZES §16.16): за день чи тиждень їх замало, щоб рахувати.
        if !compact, case .month = report.period, game.prizesReceived > 0 {
            let n = game.prizesReceived
            badges.append("🎁 \(n) \(Plural.uk(n, one: "приз", few: "призи", many: "призів"))")
        }
        return badges
    }

    // MARK: - Думка (§11.4)

    private func thoughtSlide(kicker: String, emoji: String, extra: String?) -> ReportSlide {
        var headline = "Кожна склянка — крок до звички"
        var detail: String?
        var versus: [WTVersusBars.Item] = []
        switch report.thought {
        case .weakPart(let weak):
            headline = "\(weak.title.capitalizedFirst) — найслабше місце: у середньому \(ReportFormat.percent(weak.median)) % від потрібного"
            detail = "Одна склянка до \(ReportFormat.clock(weak.toMinute)) — і \(weak.title) закрито."
        case .improvement(let percent):
            headline = "На \(percent) % більше води, ніж \(previousPeriodPhrase)"
            detail = "Новий ритм уже працює."
        case .recordStreak(let days):
            headline = "Рекорд: \(ReportFormat.daysWord(days, withNumber: true)) поспіль із нормою"
            detail = "Такої серії ще не було."
        case .weekendGap(let percent, let weekendLess):
            headline = "У вихідні — на \(percent) % \(weekendLess ? "менше" : "більше") води, ніж у будні"
            if weekendLess, !weekendScheduleEnabled {
                detail = "Окремий розклад вихідних зсуне ранкову склянку й нагадування на пізніше."
            }
            if let weekday = report.weekdayAverageMl, let weekend = report.weekendAverageMl {
                let scale = Double(max(weekday, weekend, 1))
                versus = [.init(value: ReportFormat.volume(weekday, unit), label: "БУДНІ", fraction: Double(weekday) / scale),
                          .init(value: ReportFormat.volume(weekend, unit), label: "ВИХІДНІ", fraction: Double(weekend) / scale)]
            }
        case .bestDay(let day):
            let name = report.period.kind == .week
                ? ReportFormat.weekday(calendar.weekdayIndex(of: day.day))
                : "\(day.day.day) \(ReportFormat.monthGenitive(day.day.month))"
            headline = "Найкращий день — \(name), \(ReportFormat.volume(day.totalMl, unit))"
            let missed = report.elapsedDays.filter { !$0.goalMet }.count
            let span = report.period.kind == .week ? "тиждень" : "місяць"
            detail = missed == 0
                ? "\(span.capitalizedFirst) без пропусків — так тримати."
                : "Ще \(ReportFormat.daysWord(missed, withNumber: true)) з нормою — і \(span) був би без пропусків."
        case .strongestPart(let title, let percent):
            headline = "\(title.capitalizedFirst) — найсильніша частина: \(percent) % від потрібного"
        case nil:
            break
        }
        return .thought(kicker: kicker, emoji: emoji, headline: headline, detail: extra ?? detail, versus: versus)
    }

    private var previousPeriodPhrase: String {
        switch report.period {
        case .day: return "учора"
        case .week: return "минулого тижня"
        case .month(let month): return "у \(ReportFormat.monthLocative(calendar.monthKey(offsetMonths: -1, from: month).month))"
        }
    }

    private func changePill(suffix: String) -> ReportSlide.Pill? {
        guard let change = report.averageChangePercent, change != 0 else { return nil }
        return .init(text: "\(change > 0 ? "▲" : "▼") \(abs(change)) % \(suffix)", positive: change > 0)
    }

    private var glassesText: String {
        let n = report.glasses
        return "\(n) \(Plural.uk(n, one: "склянка", few: "склянки", many: "склянок"))"
    }
}

/// Числа й назви для звіту. Кома десяткова, як у сповіщеннях (рішення від 05.10.2026):
/// звіт — розповідь, а не таблиця, і «1,8 л» тут читається природніше.
enum ReportFormat {
    /// Велике число обкладинки: до літра — мілілітри, далі — літри.
    static func big(_ ml: Int, _ system: VolumeUnit = .milliliters) -> (value: Double, decimals: Int, unit: String) {
        guard system.isMetric else { return (Double(system.units(ml)), 0, VolumeUnit.ounceSymbol) }
        guard ml >= 1000 else { return (Double(ml), 0, "мл") }
        let value = liters(ml)
        return (value.value, value.decimals, "л")
    }

    static func liters(_ ml: Int) -> (value: Double, decimals: Int) {
        let liters = Double(ml) / 1000
        let rounded = (liters * 10).rounded() / 10
        return (rounded, abs(rounded - rounded.rounded()) < 0.05 ? 0 : 1)
    }

    /// «850 мл», «1,9 л», «52 л».
    static func volume(_ ml: Int, _ system: VolumeUnit = .milliliters) -> String {
        guard system.isMetric else { return system.portion(ml) }
        guard ml >= 1000 else { return "\(ml) мл" }
        let (value, decimals) = liters(ml)
        return String(format: "%.\(decimals)f", value).replacingOccurrences(of: ".", with: ",") + " л"
    }

    static func percent(_ ratio: Double) -> Int { Int((ratio * 100).rounded()) }

    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60) }

    /// «днів» або з числом — «12 днів».
    static func daysWord(_ n: Int, withNumber: Bool = false) -> String {
        withNumber ? Plural.days(n) : Plural.uk(n, one: "день", few: "дні", many: "днів")
    }

    static let weekdays = ["понеділок", "вівторок", "середа", "четвер", "пʼятниця", "субота", "неділя"]
    static func weekday(_ index: Int) -> String { weekdays[max(0, min(6, index))] }
    static func weekdayShort(_ index: Int) -> String { CalendarService.weekdayLabels[max(0, min(6, index))] }

    static func monthName(_ month: Int) -> String { CalendarService.monthNames[max(1, min(12, month)) - 1] }
    static func monthGenitive(_ month: Int) -> String { CalendarService.monthNamesGenitive[max(1, min(12, month)) - 1] }
    static let monthsLocative = ["січні", "лютому", "березні", "квітні", "травні", "червні",
                                 "липні", "серпні", "вересні", "жовтні", "листопаді", "грудні"]
    static func monthLocative(_ month: Int) -> String { monthsLocative[max(1, min(12, month)) - 1] }
}

extension String {
    /// «ранок і полудень» → «Ранок і полудень».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
