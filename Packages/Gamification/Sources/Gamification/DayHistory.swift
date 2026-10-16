import Foundation
import Core
import Persistence

/// Сезон для «Літа», «Зими» й «Чотирьох сезонів» — метеорологічний, північна півкуля.
/// Зима — грудень одного року й січень–лютий наступного.
public enum Season: Int, Sendable, Hashable, CaseIterable {
    case winter = 0, spring, summer, autumn
}

/// Факт історії днів — правило досягнення, що рахується з денних записів, а не з лічильників шини
/// (SPEC-ACHIEVEMENTS-CATALOG §6). Історія — джерело правди, як і для серій: відкат порції чи
/// заморозка дають правильне значення без окремої «зворотної» логіки, а після оновлення досягнення
/// відкриваються заднім числом.
///
/// **Умови, які зіпсувало б доливання води** («Влучність», «В яблучко», «Дзеркало», «Як дві краплі
/// води», «Рівна крива»), дивляться лише на **завершені** дні: інакше 102 % о 20:00 відкрили б
/// «Влучність», а 110 % о 22:00 — закрили б її першим-ліпшим відкатом. Решта монотонні щодо нових
/// порцій і бачать сьогодні одразу.
public enum HistoryFact: Sendable, Hashable {
    // Вода
    /// Зараховане за весь час, мл — у межах стелі 120 % (принцип 1).
    case countedMl
    case bestEntriesInDay

    // Регулярність
    case goalDays
    /// Днів хоч з однією порцією.
    case activeDays
    /// Найдовше «поспіль хоч з однією порцією». Заморозка тут не допомагає: вона про норму, а не про воду.
    case activeDaysRun
    /// Найдовше «без двох пропусків поспіль». Пропуск — день без норми, заморожений день — не пропуск.
    case neverTwiceRun
    /// Найдовше «поспіль від `percent` % норми». Заморожений день тримає ланцюг, але не додає — як у серії.
    case noDipsRun(percent: Int)
    /// Найдовше «тижнів поспіль, у кожному від `minGoalDays` днів із нормою» (тиждень — з понеділка).
    case stableWeeksRun(minGoalDays: Int)

    // Серії й повернення
    /// Скільки разів норма наступного дня після обриву серії ≥ `minStreak` — правило XP «Знову в ритмі».
    case bounceBacks(minStreak: Int)
    /// Нова серія після обриву серії ≥ `minStreak`: значення — найдовша з наступних серій.
    case secondWave(minStreak: Int)
    /// Після перерви ≥ `breakDays` днів без порцій — найдовше «поспіль із нормою» до наступної такої перерви.
    case backAfterBreak(breakDays: Int)
    /// Порція після ≥ `days` днів без порцій: 1 чи 0.
    case returnAfterBreak(days: Int)
    /// Серія ≥ `minStreak`, довша за всі попередні: 1 чи 0.
    case recordBeaten(minStreak: Int)
    /// Скільки заморожених днів продовжили серію ≥ `minStreak`.
    case freezeSaves(minStreak: Int)

    // Ритм дня
    case morningGoalDays
    case allBlocksDays
    /// Перша порція — не пізніше ніж за `withinMinutes` після підйому.
    case wakeGlassDays(withinMinutes: Int)
    /// Норма закрита щонайменше за `minutesBeforeSleep` до відбою.
    case quietEveningDays(minutesBeforeSleep: Int)
    /// Найкращий бал «Рівномірності за день» серед завершених днів.
    case bestEvenness

    // Статистика
    /// Завершених днів, коли випито `fromPercent`…`toPercent` % норми.
    case accurateDays(fromPercent: Int, toPercent: Int)
    /// Завершених днів, коли випито рівно норму.
    case exactGoalDays
    case bestMonthGoalDays
    /// Календарних місяців із нормою щодня. Заморозка не допомагає.
    case perfectMonths

    // Календар і фанові
    /// Вихідних (субота й неділя), коли норма в обидва дні.
    case goalWeekends
    case goalWeekendsRun
    /// Найбільше днів із нормою за один сезон цього виду.
    case seasonGoalDays(Season)
    /// Скільки видів сезону мали ≥ `minDays` днів із нормою (до 4).
    case seasonsWithGoalDays(minDays: Int)
    /// Порція рівно через рік (два, три…) від першої.
    case anniversary
    /// Днів, коли до 12:00 випито пів норми.
    case halfGoalBeforeNoonDays
    case portionOnDate(month: Int, day: Int)
    case goalOnDate(month: Int, day: Int)
    case goalOnSolstice(SkyCalendar.Solstice)
    case portionOnFullMoon
    case portionOnFriday13
    /// Два завершені дні поспіль з однаковим об'ємом, до мілілітра.
    case twinDays
    /// Порція в поясі, що зміщений відносно поясу першої порції.
    case otherTimeZone
    case portionOfMl(Int)
    /// Порція о хвилині доби (`hour × 60 + minute`).
    case portionAtMinute(Int)
    /// `times` порцій додано й скасовано в межах `withinSeconds`.
    case indecision(times: Int, withinSeconds: Int)
    /// Завершений день з об'ємом-паліндромом від `minMl`.
    case palindromeDay(minMl: Int)
    /// Скільки груп джерел порцій уже траплялось: «Усі шляхи» — 4 групи, «Голосом» — 1 (Siri чи «Команди»).
    case sourceGroups([[IntakeSource]])
    /// Днів, коли діяв буст і закрито норму.
    case boostGoalDays
}

extension HistoryFact {
    /// Факт дивиться лише на завершені дні — сьогоднішня порція його не змінює.
    var onlyFinishedDays: Bool {
        switch self {
        case .bestEvenness, .accurateDays, .exactGoalDays, .twinDays, .palindromeDay: return true
        default: return false
        }
    }
}

/// Один день історії: зріз `DayLog` і його порцій без SwiftData — правила ходять сотнями днів.
/// Клас, а не структура: множини й масиви всередині робили кожне сортування й копію історії дорогими.
final class DayRecord {
    let ordinal: Int
    let year: Int
    let month: Int
    let day: Int
    let goalMl: Int
    let totalMl: Int
    let countedMl: Int
    let entries: Int
    let goalMet: Bool
    let firstMinute: Int?
    /// Хвилина порції, що закрила норму.
    let goalMinute: Int?
    let wakeMinutes: Int
    let sleepMinutes: Int
    let morningReached: Bool
    let allBlocksReached: Bool
    let evenness: Int
    let beforeNoonMl: Int
    let timeZoneId: String
    let amounts: Set<Int>
    let minutes: Set<Int>
    let sources: Set<IntakeSource>
    /// Скасовані порції — для «Нерішучості».
    let cancelled: [(added: Date, removed: Date)]
    let isActive: Bool

    init(ordinal: Int, year: Int, month: Int, day: Int, goalMl: Int, totalMl: Int, countedMl: Int, entries: Int,
         goalMet: Bool, firstMinute: Int?, goalMinute: Int?, wakeMinutes: Int, sleepMinutes: Int,
         morningReached: Bool, allBlocksReached: Bool, evenness: Int, beforeNoonMl: Int, timeZoneId: String,
         amounts: Set<Int>, minutes: Set<Int>, sources: Set<IntakeSource>, cancelled: [(added: Date, removed: Date)]) {
        self.ordinal = ordinal
        self.year = year
        self.month = month
        self.day = day
        self.goalMl = goalMl
        self.totalMl = totalMl
        self.countedMl = countedMl
        self.entries = entries
        self.goalMet = goalMet
        self.firstMinute = firstMinute
        self.goalMinute = goalMinute
        self.wakeMinutes = wakeMinutes
        self.sleepMinutes = sleepMinutes
        self.morningReached = morningReached
        self.allBlocksReached = allBlocksReached
        self.evenness = evenness
        self.beforeNoonMl = beforeNoonMl
        self.timeZoneId = timeZoneId
        self.amounts = amounts
        self.minutes = minutes
        self.sources = sources
        self.cancelled = cancelled
        self.isActive = entries > 0 || totalMl > 0
    }
}

/// Історія днів для правил досягнень (WAT-24): кеш `DayRecord` з точковим оновленням.
///
/// Повне читання — лише на старті й новій добі (`reload()`); порція оновлює один день
/// (`invalidate(day:)`). Значення фактів запам'ятовуються до зміни входів: 115 правил на кожну
/// з 3–4 подій порції інакше ходили б історією по колу (межа `PerformanceTests`).
@MainActor
final class DayHistory {
    private let dayLogs: DayLogRepositoryProtocol
    private let calendar: CalendarService
    private let profile: () -> UserProfile

    private var records: [Int: DayRecord] = [:]
    private var sortedCache: [DayRecord]?
    private var isLoaded = false
    private var staleDays: Set<String> = []

    private var today = 0
    private var frozen: Set<Int> = []
    private var boostDays: Set<Int> = []
    private var memo: [HistoryFact: Double] = [:]
    private var solsticeCache: [SolsticeKey: Int] = [:]
    private var fullMoonCache: (range: ClosedRange<Int>, days: Set<Int>)?

    private struct SolsticeKey: Hashable { let kind: SkyCalendar.Solstice; let year: Int }

    init(dayLogs: DayLogRepositoryProtocol, calendar: CalendarService, profile: @escaping () -> UserProfile) {
        self.dayLogs = dayLogs
        self.calendar = calendar
        self.profile = profile
    }

    /// Повне перечитування — старт, нова доба, перемикання поясу.
    func reload() {
        isLoaded = false
        staleDays.removeAll()
        fullMoonCache = nil
        solsticeCache.removeAll()
    }

    /// Запис дня змінився: порція, відкат, повернення.
    func invalidate(day: String) {
        staleDays.insert(day)
    }

    /// Входи, від яких залежать факти. Будь-яка зміна скидає запам'ятовані значення.
    func prepare(today day: DayKey, frozenDays: [String], boostDays boosts: Set<String>) {
        let todayOrdinal = day.ordinal
        let frozenSet = Set(frozenDays.map { DayKey(rawValue: $0).ordinal })
        let boostSet = Set(boosts.map { DayKey(rawValue: $0).ordinal })
        if todayOrdinal != today || frozenSet != frozen || boostSet != boostDays {
            today = todayOrdinal
            frozen = frozenSet
            boostDays = boostSet
            resetDerived()
        }
        if !isLoaded {
            records = Dictionary(dayLogs.allDayLogs().map(record(from:)).map { ($0.ordinal, $0) },
                                 uniquingKeysWith: { _, last in last })
            isLoaded = true
            staleDays.removeAll()
            resetDerived()
        }
        guard !staleDays.isEmpty else { return }
        let refreshed = staleDays.map { DayKey(rawValue: $0) }
        staleDays.removeAll()
        for key in refreshed {
            records[key.ordinal] = dayLogs.existingDayLog(for: key).map(record(from:))
        }
        // Порція змінює лише сьогоднішній день — латаємо його в готових масивах, а не будуємо їх наново.
        if refreshed.count == 1, refreshed[0].ordinal == today, patchToday() {
            // Факти лише завершених днів від сьогоднішньої порції не змінюються.
            memo = memo.filter { $0.key.onlyFinishedDays }
        } else {
            resetDerived()
        }
    }

    /// Сьогоднішній запис змінився: оновити останній елемент упорядкованої історії й останній день стрічки.
    /// `false` — латати нічого (кешів ще немає чи сьогодні не останній день): тоді перебудова.
    private func patchToday() -> Bool {
        guard var sorted = sortedCache, let line = timelineCache, line.first + line.last == today else { return false }
        let record = records[today]
        if sorted.last?.ordinal == today { sorted.removeLast() }
        if let record { sorted.append(record) }
        sortedCache = sorted

        var days = line.days, goal = line.goal, counted = line.counted, active = line.active, chain = line.chain
        let index = line.last
        days[index] = record
        goal[index] = record?.goalMet ?? false
        counted[index] = goal[index] || frozen.contains(today)
        active[index] = record?.isActive ?? false
        let previous = index > 0 ? chain[index - 1] : 0
        chain[index] = counted[index] ? previous + (goal[index] ? 1 : 0) : 0
        timelineCache = Timeline(first: line.first, days: days, goal: goal, counted: counted, active: active, chain: chain)

        // Завершені дні сьогоднішній запис не зачіпає; активні й серії — так.
        activeCache = nil
        runsCache = nil
        return true
    }

    func value(of fact: HistoryFact) -> Double {
        if let cached = memo[fact] { return cached }
        let value = compute(fact)
        memo[fact] = value
        return value
    }

    // MARK: - Зріз дня

    private func record(from log: DayLog) -> DayRecord {
        let key = DayKey(rawValue: log.dayKey)
        let all = log.intakes ?? []
        let active = all.filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }
        let portions = active.map { TimedPortion(minute: calendar.minuteOfDay($0.createdAt), ml: $0.amountMl) }
        // Розклад — із запису дня: зміна підйому пізніше не переписує минулих днів (WAT-39).
        let schedule = profile().schedule(for: log, isWeekend: calendar.isWeekend(key))
        let curve = schedule.curve(goalMl: log.goalMlSnapshot)
        let blocks = curve.goalBlocks()

        var running = 0
        var goalMinute: Int?
        for portion in portions {
            running += portion.ml
            if goalMinute == nil, running >= log.goalMlSnapshot { goalMinute = portion.minute }
        }

        return DayRecord(
            ordinal: key.ordinal, year: key.year, month: key.month, day: key.day,
            goalMl: log.goalMlSnapshot, totalMl: log.totalMl, countedMl: log.countedMl,
            entries: max(active.count, log.entriesCount), goalMet: log.goalMet,
            firstMinute: portions.first?.minute, goalMinute: goalMinute,
            wakeMinutes: schedule.wakeMinutes, sleepMinutes: schedule.sleepMinutes,
            morningReached: blocks.first?.isReached(by: portions) ?? false,
            allBlocksReached: !blocks.isEmpty && !portions.isEmpty && blocks.allSatisfy { $0.isReached(by: portions) },
            evenness: Evenness.score(partTotals: log.partTotals, shares: curve.partShares()),
            beforeNoonMl: portions.filter { $0.minute < 12 * 60 }.reduce(0) { $0 + $1.ml },
            timeZoneId: log.timeZoneId,
            amounts: Set(active.map(\.amountMl)),
            minutes: Set(portions.map(\.minute)),
            sources: Set(active.map(\.source)),
            cancelled: all.compactMap { intake in intake.deletedAt.map { (intake.createdAt, $0) } }
                .sorted { $0.added < $1.added }
        )
    }

    // MARK: - Обчислення

    /// Історія щільними масивами від першого дня до сьогодні — один прохід на версію входів. Факти ходять
    /// днями, і словник на кожен крок робив рік історії втричі дорожчим (`PerformanceTests`).
    private struct Timeline {
        let first: Int
        let days: [DayRecord?]
        let goal: [Bool]
        let counted: [Bool]
        let active: [Bool]
        /// Довжина серії, що закінчується на дні: лише дні з нормою, заморожені тримають ланцюг (як `StreakEngine`).
        let chain: [Int]

        var count: Int { days.count }
        var last: Int { count - 1 }

        func index(of ordinal: Int) -> Int? {
            let index = ordinal - first
            return index >= 0 && index < count ? index : nil
        }
    }

    private var timelineCache: Timeline?
    private var runsCache: [(start: Int, end: Int, length: Int)]?
    private var finishedCache: [DayRecord]?
    private var activeCache: [DayRecord]?

    private func resetDerived() {
        sortedCache = nil
        timelineCache = nil
        runsCache = nil
        finishedCache = nil
        activeCache = nil
        memo.removeAll(keepingCapacity: true)
    }

    private var sorted: [DayRecord] {
        if let sortedCache { return sortedCache }
        let result = records.values.filter { $0.ordinal <= today }.sorted { $0.ordinal < $1.ordinal }
        sortedCache = result
        return result
    }

    private var finished: [DayRecord] {
        if let finishedCache { return finishedCache }
        let result = sorted.filter { $0.ordinal < today }
        finishedCache = result
        return result
    }

    private var active: [DayRecord] {
        if let activeCache { return activeCache }
        let result = sorted.filter(\.isActive)
        activeCache = result
        return result
    }

    private var timeline: Timeline? {
        if let timelineCache { return timelineCache }
        guard let first = sorted.first?.ordinal, first <= today else { return nil }
        var days = [DayRecord?](repeating: nil, count: today - first + 1)
        for record in sorted { days[record.ordinal - first] = record }
        let goal = days.map { $0?.goalMet ?? false }
        let counted = goal.indices.map { goal[$0] || frozen.contains(first + $0) }
        var chain = [Int](repeating: 0, count: days.count)
        var length = 0
        for index in days.indices {
            if counted[index] {
                length += goal[index] ? 1 : 0
                chain[index] = length
            } else {
                length = 0
            }
        }
        let result = Timeline(first: first, days: days, goal: goal, counted: counted,
                              active: days.map { $0?.isActive ?? false }, chain: chain)
        timelineCache = result
        return result
    }

    private func goal(_ ordinal: Int) -> Bool {
        guard let line = timeline, let index = line.index(of: ordinal) else { return false }
        return line.goal[index]
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func compute(_ fact: HistoryFact) -> Double {
        switch fact {
        case .countedMl:
            return Double(sorted.reduce(0) { $0 + $1.countedMl })
        case .bestEntriesInDay:
            return Double(sorted.map(\.entries).max() ?? 0)
        case .goalDays:
            return Double(sorted.filter(\.goalMet).count)
        case .activeDays:
            return Double(active.count)
        case .activeDaysRun:
            return Double(bestRun { line, index in
                line.active[index] ? .adds : (index == line.last ? .pending : .breaks)
            })
        case .neverTwiceRun:
            return Double(neverTwiceRun())
        case .noDipsRun(let percent):
            return Double(bestRun { line, index in
                if let record = line.days[index], record.goalMl > 0, record.countedMl * 100 >= record.goalMl * percent {
                    return .adds
                }
                if line.counted[index] { return .holds }
                return index == line.last ? .pending : .breaks
            })
        case .stableWeeksRun(let minGoalDays):
            return Double(stableWeeksRun(minGoalDays: minGoalDays))
        case .bounceBacks(let minStreak):
            return Double(bounceBacks(minStreak: minStreak))
        case .secondWave(let minStreak):
            return Double(secondWave(minStreak: minStreak))
        case .backAfterBreak(let breakDays):
            return Double(backAfterBreak(breakDays: breakDays))
        case .returnAfterBreak(let days):
            return zip(active, active.dropFirst()).contains { $1.ordinal - $0.ordinal - 1 >= days } ? 1 : 0
        case .recordBeaten(let minStreak):
            return recordBeaten(minStreak: minStreak) ? 1 : 0
        case .freezeSaves(let minStreak):
            guard let line = timeline else { return 0 }
            return Double(frozen.filter { ordinal in
                guard ordinal < today, let index = line.index(of: ordinal - 1) else { return false }
                return line.chain[index] >= minStreak
            }.count)
        case .morningGoalDays:
            return Double(sorted.filter(\.morningReached).count)
        case .allBlocksDays:
            return Double(sorted.filter(\.allBlocksReached).count)
        case .wakeGlassDays(let within):
            return Double(sorted.filter { record in
                guard let first = record.firstMinute else { return false }
                return first >= record.wakeMinutes && first <= record.wakeMinutes + within
            }.count)
        case .quietEveningDays(let before):
            return Double(sorted.filter { record in
                guard let minute = record.goalMinute else { return false }
                return minute <= record.sleepMinutes - before
            }.count)
        case .bestEvenness:
            return Double(finished.filter(\.isActive).map(\.evenness).max() ?? 0)
        case .accurateDays(let from, let to):
            return Double(finished.filter { record in
                record.goalMl > 0 && record.totalMl * 100 >= record.goalMl * from
                    && record.totalMl * 100 <= record.goalMl * to
            }.count)
        case .exactGoalDays:
            return Double(finished.filter { $0.goalMl > 0 && $0.totalMl == $0.goalMl }.count)
        case .bestMonthGoalDays:
            return Double(goalDaysByMonth().values.max() ?? 0)
        case .perfectMonths:
            return Double(goalDaysByMonth().filter { key, count in
                count == DayKey.daysIn(year: key / 12, month: key % 12 + 1)
            }.count)
        case .goalWeekends:
            return Double(saturdays().filter { goal($0) && goal($0 + 1) }.count)
        case .goalWeekendsRun:
            return Double(goalWeekendsRun())
        case .seasonGoalDays(let season):
            return Double(seasonGoalDays()[season] ?? 0)
        case .seasonsWithGoalDays(let minDays):
            return Double(seasonGoalDays().values.filter { $0 >= minDays }.count)
        case .anniversary:
            return anniversary() ? 1 : 0
        case .halfGoalBeforeNoonDays:
            return Double(sorted.filter { $0.goalMl > 0 && $0.beforeNoonMl * 2 >= $0.goalMl }.count)
        case .portionOnDate(let month, let day):
            return active.contains { $0.month == month && $0.day == day } ? 1 : 0
        case .goalOnDate(let month, let day):
            return sorted.contains { $0.goalMet && $0.month == month && $0.day == day } ? 1 : 0
        case .goalOnSolstice(let kind):
            return sorted.contains { $0.goalMet && $0.ordinal == solsticeOrdinal(kind, year: $0.year) } ? 1 : 0
        case .portionOnFullMoon:
            let moons = fullMoonDays()
            return active.contains { moons.contains($0.ordinal) } ? 1 : 0
        case .portionOnFriday13:
            return active.contains { $0.day == 13 && DayKey.weekdayIndex(ordinal: $0.ordinal) == 4 } ? 1 : 0
        case .twinDays:
            let days = finished
            return zip(days, days.dropFirst()).contains { lhs, rhs in
                rhs.ordinal == lhs.ordinal + 1 && lhs.totalMl > 0 && lhs.totalMl == rhs.totalMl
            } ? 1 : 0
        case .otherTimeZone:
            return otherTimeZone() ? 1 : 0
        case .portionOfMl(let ml):
            return active.contains { $0.amounts.contains(ml) } ? 1 : 0
        case .portionAtMinute(let minute):
            return active.contains { $0.minutes.contains(minute) } ? 1 : 0
        case .indecision(let times, let seconds):
            return sorted.contains { Self.hasIndecision($0.cancelled, times: times, seconds: seconds) } ? 1 : 0
        case .palindromeDay(let minMl):
            return finished.contains { $0.totalMl >= minMl && Self.isPalindrome($0.totalMl) } ? 1 : 0
        case .sourceGroups(let groups):
            let used = active.reduce(into: Set<IntakeSource>()) { $0.formUnion($1.sources) }
            return Double(groups.filter { !used.isDisjoint(with: $0) }.count)
        case .boostGoalDays:
            return Double(boostDays.filter(goal).count)
        }
    }

    // MARK: - Ланцюги

    private enum Step { case adds, holds, breaks, pending }

    /// Найдовший ланцюг від першого дня історії до сьогодні. `pending` — сьогодні ще не вирішено:
    /// день не додає й не рве ланцюг (норму можна закрити до вечора).
    private func bestRun(_ step: (Timeline, Int) -> Step) -> Int {
        guard let line = timeline else { return 0 }
        var best = 0
        var run = 0
        for index in 0..<line.count {
            switch step(line, index) {
            case .adds: run += 1
            case .holds, .pending: break
            case .breaks: run = 0
            }
            best = max(best, run)
        }
        return best
    }

    /// «Ніколи двічі»: один пропуск ланцюг не рве, два поспіль — рахунок з нуля. Пропуск — день без
    /// норми (заморожений — не пропуск). Сьогодні без норми ще не пропуск.
    private func neverTwiceRun() -> Int {
        guard let line = timeline else { return 0 }
        var best = 0
        var run = 0
        var previousMissed = false
        for index in 0..<line.count {
            let missed = !line.counted[index]
            if index == line.last && missed { break }
            if missed && previousMissed {
                run = 0
            } else {
                run += 1
            }
            previousMissed = missed
            best = max(best, run)
        }
        return best
    }

    /// Серії в хронологічному порядку: перший і останній день ланцюга й кількість днів із нормою.
    private func runs() -> [(start: Int, end: Int, length: Int)] {
        if let runsCache { return runsCache }
        guard let line = timeline else { return [] }
        var result: [(start: Int, end: Int, length: Int)] = []
        var start: Int?
        for index in 0..<line.count {
            if line.counted[index] {
                if start == nil { start = index }
            } else if let begin = start {
                result.append((line.first + begin, line.first + index - 1, line.chain[index - 1]))
                start = nil
            }
        }
        if let begin = start { result.append((line.first + begin, line.first + line.last, line.chain[line.last])) }
        let runs = result.filter { $0.length > 0 }
        runsCache = runs
        return runs
    }

    private func bounceBacks(minStreak: Int) -> Int {
        let all = runs()
        return zip(all, all.dropFirst()).filter { previous, next in
            next.start == previous.end + 2 && previous.length >= minStreak && goal(next.start)
        }.count
    }

    /// Серія вважається обірваною, коли після неї є пропущений завершений день.
    private func secondWave(minStreak: Int) -> Int {
        let all = runs()
        guard let index = all.firstIndex(where: { $0.length >= minStreak && $0.end < today - 1 }) else { return 0 }
        return all[(index + 1)...].map(\.length).max() ?? 0
    }

    private func recordBeaten(minStreak: Int) -> Bool {
        var best = 0
        for (index, run) in runs().enumerated() {
            if index > 0, run.length >= minStreak, run.length > best { return true }
            best = max(best, run.length)
        }
        return false
    }

    /// Відрізок після перерви триває до наступної такої ж перерви: у ній немає порцій, тож ланцюг
    /// норми там і так обривається.
    private func backAfterBreak(breakDays: Int) -> Int {
        guard let line = timeline else { return 0 }
        let days = active
        let starts = zip(days, days.dropFirst())
            .filter { previous, next in next.ordinal - previous.ordinal - 1 >= breakDays }
            .map { $1.ordinal - line.first }
        var best = 0
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : line.count
            var run = 0
            for day in start..<end {
                if line.goal[day] { run += 1 } else if day != line.last { run = 0 }
                best = max(best, run)
            }
        }
        return best
    }

    private func stableWeeksRun(minGoalDays: Int) -> Int {
        guard let line = timeline else { return 0 }
        func week(_ ordinal: Int) -> Int { (ordinal + 3) / 7 }
        var counts: [Int: Int] = [:]
        for index in 0..<line.count where line.goal[index] { counts[week(line.first + index), default: 0] += 1 }
        let current = week(today)
        var best = 0
        var run = 0
        for index in week(line.first)...current {
            if (counts[index] ?? 0) >= minGoalDays {
                run += 1
            } else if index != current {
                run = 0
            }
            best = max(best, run)
        }
        return best
    }

    // MARK: - Календар

    /// Ключ місяця — `рік × 12 + (місяць − 1)`.
    private func goalDaysByMonth() -> [Int: Int] {
        var result: [Int: Int] = [:]
        for record in sorted where record.goalMet { result[record.year * 12 + record.month - 1, default: 0] += 1 }
        return result
    }

    private func saturdays() -> [Int] {
        guard let line = timeline else { return [] }
        let offset = (5 - DayKey.weekdayIndex(ordinal: line.first) + 7) % 7
        return Array(stride(from: line.first + offset, through: today, by: 7))
    }

    private func goalWeekendsRun() -> Int {
        var best = 0
        var run = 0
        for saturday in saturdays() {
            if goal(saturday) && goal(saturday + 1) {
                run += 1
            } else if saturday + 1 < today {
                run = 0
            }
            best = max(best, run)
        }
        return best
    }

    /// Найбільше днів із нормою за один сезон кожного виду.
    private func seasonGoalDays() -> [Season: Int] {
        var bySeason: [Int: Int] = [:]
        for record in sorted where record.goalMet {
            bySeason[(record.year * 12 + record.month) / 3, default: 0] += 1
        }
        var result: [Season: Int] = [:]
        for (index, count) in bySeason {
            guard let season = Season(rawValue: index % 4) else { continue }
            result[season] = max(result[season] ?? 0, count)
        }
        return result
    }

    private func anniversary() -> Bool {
        let days = active
        guard let first = days.first else { return false }
        return days.contains { record in
            guard record.year > first.year else { return false }
            if record.month == first.month && record.day == first.day { return true }
            // Перша порція 29 лютого — річниця 28-го в невисокосний рік.
            return first.month == 2 && first.day == 29 && !DayKey.isLeapYear(record.year)
                && record.month == 2 && record.day == 28
        }
    }

    private func solsticeOrdinal(_ kind: SkyCalendar.Solstice, year: Int) -> Int {
        let key = SolsticeKey(kind: kind, year: year)
        if let cached = solsticeCache[key] { return cached }
        let ordinal = calendar.dayKey(for: SkyCalendar.solstice(kind, year: year)).ordinal
        solsticeCache[key] = ordinal
        return ordinal
    }

    /// Дні повні між першим днем історії й сьогодні — у поясі годинника.
    private func fullMoonDays() -> Set<Int> {
        guard let first = sorted.first?.ordinal, first <= today else { return [] }
        if let cached = fullMoonCache, cached.range == first...today { return cached.days }
        let from = calendar.date(from: DayKey(ordinal: first))
        let to = calendar.date(from: DayKey(ordinal: today + 1))
        let days = Set(SkyCalendar.fullMoons(from: from, to: to).map { calendar.dayKey(for: $0).ordinal })
        fullMoonCache = (first...today, days)
        return days
    }

    /// Пояс першої порції проти поясу кожної наступної — за зміщенням у ту саму мить: «Europe/Kiev» і
    /// «Europe/Kyiv» — один пояс, а перехід на літній час — не переліт.
    private func otherTimeZone() -> Bool {
        let days = active
        guard let home = days.first.flatMap({ TimeZone(identifier: $0.timeZoneId) }) else { return false }
        var zones: [String: TimeZone] = [:]
        return days.dropFirst().contains { record in
            guard record.timeZoneId != home.identifier else { return false }
            let zone = zones[record.timeZoneId] ?? TimeZone(identifier: record.timeZoneId)
            zones[record.timeZoneId] = zone
            guard let zone else { return false }
            let moment = calendar.date(from: DayKey(ordinal: record.ordinal)).addingTimeInterval(12 * 3600)
            return zone.secondsFromGMT(for: moment) != home.secondsFromGMT(for: moment)
        }
    }

    // MARK: - Чисті перевірки

    static func isPalindrome(_ value: Int) -> Bool {
        let digits = String(value)
        return digits == String(digits.reversed())
    }

    /// `times` скасованих порцій поспіль, від першого додавання до останнього скасування — не довше `seconds`.
    static func hasIndecision(_ cancelled: [(added: Date, removed: Date)], times: Int, seconds: Int) -> Bool {
        guard times > 0, cancelled.count >= times else { return false }
        for start in 0...(cancelled.count - times) {
            let window = cancelled[start..<(start + times)]
            let last = window.map(\.removed).max() ?? .distantFuture
            if last.timeIntervalSince(window.first!.added) <= Double(seconds) { return true }
        }
        return false
    }
}
