import Foundation
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
@testable import Features

/// Перший тиждень новачка (WAT-29, WAT-60): 7 днів порцій через `HomeViewModel` на `FixedClock` — що людина
/// побачила й відчула. Спільне для звіту аудиту (`AttentionAuditWeek1Tests`, на вимогу) і постійної перевірки
/// бюджету досягнень (`AchievementBudgetTests`).
@MainActor
final class FirstWeekSimulation {

    // MARK: - Сценарій

    /// Порція: година, хвилина, об'єм. `custom` — через «Інше», `undo` — додати й одразу видалити (помилка).
    struct Portion {
        let hour: Int, minute: Int, ml: Int
        var custom = false
        var undo = false
    }

    /// Пн 2 — Нд 8 листопада 2026: без повні (24.11), сонцестояння, 1 квітня й інших дат таємних.
    /// Кнопки — типові 200 / 500 / 1000. Норма закрита в дні 1, 2, 3, 5, 7: серія 3 → пропуск → «Знову в ритмі».
    /// День 2 — рівно 2000 мл (200 і 500 мл легко дають рівне число): до WAT-60 це давало «В яблучко» наступного ранку.
    /// Порції не ставимо рівно на 20:00: о цій хвилині приходить вечірнє, і збіг ховав би його з підрахунку.
    static let typicalWeek: [[Portion]] = [
        // 1 Пн: перший запуск 08:40, онбординг. 2100 мл ✓
        [.init(hour: 8, minute: 45, ml: 200), .init(hour: 10, minute: 30, ml: 500), .init(hour: 13, minute: 0, ml: 200),
         .init(hour: 15, minute: 30, ml: 500), .init(hour: 18, minute: 0, ml: 200), .init(hour: 20, minute: 30, ml: 500)],
        // 2 Вт: 7 порцій, рівно 2000 ✓
        [.init(hour: 8, minute: 20, ml: 200), .init(hour: 10, minute: 0, ml: 200), .init(hour: 12, minute: 30, ml: 500),
         .init(hour: 14, minute: 30, ml: 200), .init(hour: 16, minute: 30, ml: 500), .init(hour: 19, minute: 0, ml: 200),
         .init(hour: 21, minute: 0, ml: 200)],
        // 3 Ср: 2100 ✓ — серія 3
        [.init(hour: 8, minute: 30, ml: 500), .init(hour: 11, minute: 0, ml: 200), .init(hour: 13, minute: 30, ml: 500),
         .init(hour: 16, minute: 0, ml: 200), .init(hour: 18, minute: 30, ml: 500), .init(hour: 21, minute: 0, ml: 200)],
        // 4 Чт: 1600 ✗
        [.init(hour: 9, minute: 0, ml: 200), .init(hour: 11, minute: 30, ml: 500), .init(hour: 14, minute: 0, ml: 200),
         .init(hour: 17, minute: 0, ml: 500), .init(hour: 20, minute: 10, ml: 200)],
        // 5 Пт: 2100 ✓ — «Знову в ритмі»
        [.init(hour: 8, minute: 15, ml: 200), .init(hour: 10, minute: 30, ml: 500), .init(hour: 12, minute: 30, ml: 200),
         .init(hour: 15, minute: 0, ml: 500), .init(hour: 17, minute: 30, ml: 200), .init(hour: 20, minute: 10, ml: 500)],
        // 6 Сб: пізніший підйом, 1600 ✗
        [.init(hour: 10, minute: 0, ml: 200), .init(hour: 12, minute: 30, ml: 500), .init(hour: 15, minute: 30, ml: 200),
         .init(hour: 18, minute: 30, ml: 500), .init(hour: 21, minute: 0, ml: 200)],
        // 7 Нд: 2100 ✓ — п'ятий день із нормою
        [.init(hour: 9, minute: 30, ml: 200), .init(hour: 11, minute: 30, ml: 500), .init(hour: 14, minute: 0, ml: 500),
         .init(hour: 16, minute: 30, ml: 200), .init(hour: 19, minute: 0, ml: 500), .init(hour: 21, minute: 0, ml: 200)]
    ]

    /// «Дослідник»: той самий тиждень, плюс те, що новачок пробує сам. Кожна з цих дій — «Відкриття».
    static func explorerWeek() -> [[Portion]] {
        var week = Self.typicalWeek
        // День 1: одна порція через «Інше» (330 мл замість 200) і одна помилкова, видалена одразу.
        week[0][2] = .init(hour: 13, minute: 0, ml: 330, custom: true)
        week[0].insert(.init(hour: 13, minute: 1, ml: 500, undo: true), at: 3)
        return week
    }

    /// «Старанний» (WAT-60): стрес-тест каталогу без «Відкриттів». Норма щодня, рівно 2000 мл — 8 порцій по 250,
    /// рівномірно; через день — пів норми до полудня. Не 11:11 і не 12:00: це таємні на удачу.
    static func diligentWeek() -> [[Portion]] {
        let even: [(Int, Int)] = [(8, 10), (9, 40), (11, 0), (12, 30), (14, 0), (15, 30), (17, 15), (19, 0)]
        let early: [(Int, Int)] = [(8, 5), (9, 0), (10, 15), (11, 30), (13, 30), (15, 30), (17, 30), (19, 15)]
        let first: [(Int, Int)] = [(8, 45), (10, 0), (11, 20), (12, 40), (14, 10), (15, 40), (17, 20), (19, 10)]
        return (1...7).map { day in
            let times = day == 1 ? first : (day.isMultiple(of: 2) ? early : even)
            return times.map { Portion(hour: $0.0, minute: $0.1, ml: 250) }
        }
    }

    static let zone = TimeZone(identifier: "Europe/Kyiv")!

    private static func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 1 + day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: parts)!
    }

    // MARK: - Облік

    struct DayTally {
        var homeToasts: [String] = []
        /// Вікна відкриття (WAT-60): назви сторінок і рядок рівня.
        var celebrations: [String] = []
        var achievements: [String] = []
        var hiddenAchievements: [String] = []
        var levels: [Int] = []
        var silentLevels: [Int] = []
        var nodes: [String] = []
        var prizes: [String] = []
        var dots: [String] = []
        var sheets: [String] = []
        var haptics: [String] = []
        var quests: [String] = []
        var xp = 0
    }

    /// Одна дія людини й усе, що вона викликала, — для «найгучніших моментів».
    struct Moment {
        let day: Int
        let time: String
        let action: String
        var signals: [String] = []
    }

    private let week: [[Portion]]
    private let explorer: Bool
    private let configure: (AppServices) -> Void

    private(set) var services: AppServices!
    private var clock: FixedClock!
    private var center: InMemoryNotificationCenter!
    private var model: HomeViewModel!
    private(set) var days: [DayTally] = Array(repeating: DayTally(), count: 7)
    private(set) var moments: [Moment] = []
    private var plannedById: [String: PlannedNotification] = [:]

    private var lastDots: Set<String> = []
    private var lastUnlocked: Set<String> = []
    private var lastPending: Set<Int> = []
    private var lastPrizeIds: Set<UUID> = []
    private var lastQuestsDone: Set<String> = []
    /// Тости поточної дії: рівень без свого тоста й без рядка у вікні — «тихий».
    private var momentToasts: [String] = []
    /// Що поточна дія відсвяткувала вікном: досягнення без вікна — «тихі».
    private var momentCelebrated: Set<String> = []
    private var momentLevelRows: Set<Int> = []

    init(_ week: [[Portion]], explorer: Bool = false, configure: @escaping (AppServices) -> Void = { _ in }) {
        self.week = week
        self.explorer = explorer
        self.configure = configure
    }

    /// Субота й неділя в сценарії починаються о 09:30–10:00 — такий розклад людина задала б в онбордингу.
    static let weekendLater = WeekSchedule(
        weekday: .weekdayDefault, weekendEnabled: true, weekend: DaySchedule(wakeMinutes: 9 * 60 + 30, sleepMinutes: 23 * 60)
    )

    // MARK: - Прогін

    func run() async {
        center = InMemoryNotificationCenter(status: .notDetermined, grantsOnRequest: true)
        clock = FixedClock(now: Self.date(day: 1, 8, 40), timeZone: Self.zone)
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)

        // Перший запуск: онбординг поверх головного (повноекранний, ~11 кроків), на кроці «Нагадування» —
        // системний запит дозволу. Норма лишається 2000, склянку підтверджено.
        services.bootstrap()
        let onboardingShown = services.shouldOpenOnboarding
        services.handleBecameActive()
        model = HomeViewModel(services: services)
        snapshotBaseline()
        momentToasts = []
        var first = Moment(day: 1, time: "08:40", action: "перший запуск")
        if onboardingShown {
            days[0].sheets.append("онбординг")
            first.signals.append("онбординг")
        }
        services.profile.notificationsEnabled = true
        services.profile.glassConfirmed = true
        services.profile.onboardingState = .completed
        configure(services)
        services.profiles.save()
        await services.notifications.requestAuthorization()
        days[0].sheets.append("системний запит дозволу")
        first.signals.append("системний запит дозволу")
        services.touch()
        await settle()
        first.signals += collectDiff(day: 1)
        moments.append(first)
        await services.handleEnteredBackground()
        rememberPlan()

        for (index, portions) in week.enumerated() {
            let day = index + 1
            for (number, portion) in portions.enumerated() {
                let at = Self.date(day: day, portion.hour, portion.minute)
                momentToasts = []
                momentCelebrated = []
                momentLevelRows = []
                await open(at: at)
                var moment = Moment(day: day, time: Self.clockText(portion.hour, portion.minute),
                                    action: Self.describe(portion))
                // Відкриття зранку могло показати вікно «Поки тебе не було» (завершений учорашній день).
                moment.signals += drainCelebrations(day: day, source: Self.openingWindow)
                moment.signals += perform(portion, day: day)
                moment.signals += collectDiff(day: day)
                // Увечері, після останньої порції, — зазирнути в «Прогрес»: забрати призи шляху рівнів,
                // переглянути нові досягнення й призи. Інакше крапки світились би весь тиждень.
                if number == portions.count - 1 {
                    moment.signals += eveningCheck(day: day)
                }
                if explorer {
                    moment.signals += exploreExtras(day: day, after: number)
                }
                moments.append(moment)
                await services.handleEnteredBackground()
                rememberPlan()
            }
        }

        // Ранок восьмого дня — щоб нічні й ранкові сповіщення сьомого дня позначились доставленими.
        await open(at: Self.date(day: 8, 7))
        await services.handleEnteredBackground()
        rememberPlan()
    }

    private static func describe(_ portion: Portion) -> String {
        if portion.undo { return "+\(portion.ml) і одразу видалити" }
        return portion.custom ? "+\(portion.ml) через «Інше»" : "+\(portion.ml)"
    }

    private static func clockText(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Відкрити застосунок о `at`: повернення з фону, нова доба, перечитування головного.
    private func open(at: Date) async {
        clock.set(at)
        services.handleBecameActive()
        await settle()
        model.reload()
        rememberPlan()
    }

    private func settle() async {
        await services.notifications.rescheduleNow()
    }

    private func rememberPlan() {
        for item in services.notifications.lastPlan.items { plannedById[item.id] = item }
    }

    /// Підписи сигналів вікна — за ними `AchievementBudgetTests` рахує «одна дія — одне вікно».
    static let actionWindow = "вікно дії"
    static let openingWindow = "вікно на відкритті"
    static let screenWindow = "вікно поверх екрана"

    /// Вікно відкриття, якщо є: записати й закрити, як людина. Закрите вікно може показати наступне —
    /// відкрите, поки перше було на екрані.
    private func drainCelebrations(day: Int, source: String) -> [String] {
        var signals: [String] = []
        for _ in 0..<5 {
            guard let shown = services.celebration else { break }
            var text = shown.pages.map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")
            if let level = shown.level {
                text += " + рівень \(level.number)"
                momentLevelRows.insert(level.number)
            }
            days[min(day, 7) - 1].celebrations.append(text)
            momentCelebrated.formUnion(shown.keys)
            signals.append("\(source): \(text)")
            services.dismissCelebration(later: true)
            // Як `HomeScreen`: після вікна — крапки й шторка дозволу, що чекала.
            model.celebrationDidClose()
        }
        return signals
    }

    /// Порція на головному: вікно чи тост дії, шторки, вібрація.
    private func perform(_ portion: Portion, day: Int) -> [String] {
        var signals: [String] = []
        if portion.custom {
            model.openCustom()
            model.customAmount = portion.ml
            model.confirmCustom()
        } else {
            model.add(portion.ml)
        }
        if let pulse = model.pulse, let text = Self.haptic(pulse.kind) {
            days[day - 1].haptics.append(text)
            signals.append("вібрація: \(text)")
        }
        signals += drainCelebrations(day: day, source: Self.actionWindow)
        signals += drainToasts(day: day)
        if portion.undo, let id = model.history.first(where: { $0.amountMl == portion.ml })?.id {
            model.remove(id: id)
            // «Порцію видалено · Скасувати» — без «Скасувати»: порція справді помилкова. Вікно — після тоста.
            signals += drainToasts(day: day)
            signals += drainCelebrations(day: day, source: Self.actionWindow)
        }
        return signals
    }

    private static func haptic(_ kind: HomePulse.Kind) -> String? {
        switch kind {
        case .levelUp(let level): return "рівень \(level)"
        case .goalReached: return "норма"
        case .celebration: return "вікно"
        case .gift: return "подарунок"
        case .added, .removed, .capped: return nil
        }
    }

    /// Тост дії, потім той, що чекав у черзі, і шторка дозволу, якщо вона чекала тоста.
    private func drainToasts(day: Int) -> [String] {
        var signals: [String] = []
        while let toast = model.toast {
            days[day - 1].homeToasts.append(toast.message)
            momentToasts.append(toast.message)
            signals.append("тост: \(toast.message)")
            model.dismissToast()
        }
        if let sheet = model.sheet {
            days[day - 1].sheets.append("шторка \(sheet)")
            signals.append("шторка: \(sheet)")
            model.dismissSheet()
        }
        return signals
    }

    /// Вечірній погляд у «Прогрес» (3f) і «Досягнення» (2e).
    private func eveningCheck(day: Int) -> [String] {
        var signals: [String] = []
        let road = services.gamification.levelRoad()
        for node in road.pending {
            switch node.reward {
            case .choice(let grants)?:
                _ = services.gamification.claimChoice(level: node.level, key: grants[0].key)
                signals.append("вибір рівня \(node.level)")
            case .mystery?:
                _ = services.gamification.openMystery(level: node.level)
                signals.append("🎁 рівня \(node.level)")
            default:
                break
            }
            services.touch()
            services.presentCelebrations(context: .action)
            signals += drainCelebrations(day: day, source: Self.screenWindow)
        }
        signals += collectDiff(day: day)
        services.gamification.markAchievementsSeen()
        services.gamification.markPrizesSeen()
        snapshotDots()
        return signals
    }

    /// Що пробує «Дослідник» поза порціями: «Знання» на 2-й день, ⚡ на 3-й, темна тема на 4-й.
    private func exploreExtras(day: Int, after number: Int) -> [String] {
        var signals: [String] = []
        func announce() {
            signals += drainCelebrations(day: day, source: Self.screenWindow)
        }
        switch (day, number) {
        case (2, 1):
            // Крапка на «Знаннях» з першого дня — відкрити бібліотеку й дочитати «Перші кроки».
            services.learn.markSeen(LearnCatalog.stories.map(\.id), at: clock.now)
            services.record(.screenOpened(.learn))
            if let story = LearnCatalog.stories.first(where: { $0.id == "app.start" }) {
                services.finishLearnStory(story)
                // Як `LearnStoryScreen`: кінець паузи історії показує, що назбиралось.
                services.presentCelebrations(context: .action)
            }
            signals.append("дочитано «Перші кроки»")
            announce()
        case (3, 0):
            // ⚡ з 2-го рівня — увімкнути зранку.
            if let boost = services.gamification.prizes().first(where: { $0.key == RewardCatalog.boostKey && $0.state == .ready }) {
                _ = services.gamification.activateBoost(prizeId: boost.id)
                services.touch()
                services.presentCelebrations(context: .action)
                signals.append("увімкнено ⚡")
                announce()
            }
        case (4, 0):
            services.record(.darkTheme)
            signals.append("темна тема")
            announce()
        default:
            break
        }
        signals += collectDiff(day: day)
        return signals
    }

    // MARK: - Різниці стану

    private func snapshotBaseline() {
        lastUnlocked = Set(services.gamification.achievementSnapshots().filter(\.isUnlocked).map(\.key))
        lastPending = Set(services.gamification.levelRoad().pending.map(\.level))
        lastPrizeIds = Set(services.gamification.prizes().map(\.id))
        lastQuestsDone = []
        // Крапки, що горять з першого кадру («Знання»), — теж звернення першого дня.
        lastDots = []
    }

    private func currentDots() -> Set<String> {
        var dots: Set<String> = []
        if services.gamification.hasUnseenAchievements { dots.insert("крапля рівня (досягнення)") }
        if services.hasLearnNews { dots.insert("«Знання»") }
        if !services.gamification.levelRoad().pending.isEmpty { dots.insert("донат 3f (приз чекає)") }
        if services.gamification.hasUnseenPrizes { dots.insert("новий приз на 3f") }
        return dots
    }

    private func snapshotDots() { lastDots = currentDots() }

    /// Що змінилося з минулого виклику: досягнення, рівні, вузли, призи, завдання, крапки.
    private func collectDiff(day: Int) -> [String] {
        var signals: [String] = []
        let index = min(day, 7) - 1
        let snapshots = services.gamification.achievementSnapshots()
        let unlocked = Set(snapshots.filter(\.isUnlocked).map(\.key))
        let new = unlocked.subtracting(lastUnlocked)
        for key in new.sorted() {
            let snapshot = snapshots.first { $0.key == key }!
            let title = "\(snapshot.emoji) \(snapshot.title)"
            days[index].achievements.append(title)
            signals.append("досягнення: \(title)")
        }
        // Відкрите, яке не відсвяткувало жодне вікно цієї дії (WAT-60: кожне відкриття — вікно).
        let toastsText = momentToasts.joined(separator: " | ")
        for key in new.sorted() where !momentCelebrated.contains(key) {
            days[index].hiddenAchievements.append(snapshots.first { $0.key == key }!.title)
        }
        lastUnlocked = unlocked

        let level = services.gamification.levelProgress()
        let previous = days[..<index].flatMap(\.levels).last ?? 1
        let known = days[index].levels.last ?? previous
        if level.level > known {
            for value in (known + 1)...level.level {
                days[index].levels.append(value)
                if !toastsText.contains("Рівень \(value)!"), !momentLevelRows.contains(value) {
                    days[index].silentLevels.append(value)
                    signals.append("рівень \(value) (без тоста)")
                } else {
                    signals.append("рівень \(value)")
                }
            }
        }
        days[index].xp = level.totalXp

        let pending = Set(services.gamification.levelRoad().pending.map(\.level))
        for lvl in pending.subtracting(lastPending).sorted() {
            days[index].nodes.append("рівень \(lvl)")
            signals.append("вузол чекає дії: рівень \(lvl)")
        }
        lastPending = pending

        let prizes = services.gamification.prizes()
        for prize in prizes where !lastPrizeIds.contains(prize.id) {
            days[index].prizes.append(prize.emoji)
            signals.append("приз: \(prize.emoji) \(prize.title)")
        }
        lastPrizeIds = Set(prizes.map(\.id))

        let quests = services.gamification.dailyQuests() + services.gamification.weeklyQuests()
        let done = Set(quests.filter(\.isDone).map { "\($0.id)" })
        for quest in quests where quest.isDone && !lastQuestsDone.contains("\(quest.id)") {
            days[index].quests.append(quest.title)
            signals.append("завдання: \(quest.title)")
        }
        lastQuestsDone.formUnion(done)

        let dots = currentDots()
        for dot in dots.subtracting(lastDots).sorted() {
            days[index].dots.append(dot)
            signals.append("крапка: \(dot)")
        }
        lastDots = dots
        return signals
    }

    // MARK: - Звіт

    /// Звіт аудиту: таблиця днів, деталі, XP за джерелами й усі дії.
    func report(title: String) -> String {
        let journal = services.notifications.journal(around: clock.now)
        var delivered: [[JournalEntry]] = Array(repeating: [], count: 7)
        for entry in journal.entries where entry.status == .delivered || entry.status == .suppressed {
            guard let day = (1...7).first(where: { Self.dayKey($0) == entry.dayKey.rawValue }) else { continue }
            delivered[day - 1].append(entry)
        }

        var lines: [String] = ["", "===== \(title) ====="]
        lines.append("день | порцій | мл | тости гол. | вікна | досягн. | без вікна | рівні | рівні без свята | вузли | призи | крапки | шторки | вібр. | сповіщ. (акт/тихі) | XP")
        for (index, tally) in days.enumerated() {
            let entries = delivered[index]
            let passive = entries.filter { $0.type == .report }.count
            let portions = moments.filter { $0.day == index + 1 && $0.action.hasPrefix("+") }.count
            let ml = services.hydration.snapshot(for: DayKey(rawValue: Self.dayKey(index + 1))).totalMl
            lines.append([
                "\(index + 1)", "\(portions)", "\(ml)", "\(tally.homeToasts.count)", "\(tally.celebrations.count)",
                "\(tally.achievements.count)", "\(tally.hiddenAchievements.count)", "\(tally.levels.count)",
                "\(tally.silentLevels.count)",
                "\(tally.nodes.count)", "\(tally.prizes.count)", "\(tally.dots.count)", "\(tally.sheets.count)",
                "\(tally.haptics.count)", "\(entries.count - passive)/\(passive)", "\(tally.xp)"
            ].joined(separator: " | "))
        }

        for (index, tally) in days.enumerated() {
            lines.append("")
            lines.append("— день \(index + 1) —")
            lines.append("  тости головного: \(tally.homeToasts)")
            lines.append("  вікна відкриття: \(tally.celebrations)")
            lines.append("  досягнення: \(tally.achievements)")
            lines.append("  без вікна: \(tally.hiddenAchievements)")
            lines.append("  рівні: \(tally.levels) (без тоста й рядка: \(tally.silentLevels)); вузли: \(tally.nodes); призи: \(tally.prizes)")
            lines.append("  завдання: \(tally.quests)")
            lines.append("  крапки: \(tally.dots); шторки: \(tally.sheets); вібрація: \(tally.haptics)")
            let notes = delivered[index].sorted { $0.fireAt < $1.fireAt }.map { entry -> String in
                let time = Self.timeText(entry.fireAt)
                let planned = plannedById[entry.identifier]
                let text = planned.map { " «\($0.title)»" } ?? ""
                let followUp = planned?.priority == .reminderFollowUp ? " (повторне)" : ""
                return "\(time) \(entry.type)\(followUp)\(text)"
            }
            lines.append("  сповіщення: \(notes)")
        }

        // Звідки XP: досягнення першого дня самі піднімають рівні — і тягнуть за собою тости рівнів.
        let store = GamificationStore(context: services.container.mainContext)
        lines.append("")
        lines.append("— XP за джерелами (день: причина=XP) —")
        for day in 1...7 {
            var byReason: [String: Int] = [:]
            for entry in store.xpEntries(dayKey: Self.dayKey(day)) where entry.effectiveAmount > 0 {
                byReason["\(entry.reason)", default: 0] += entry.effectiveAmount
            }
            let parts = byReason.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }
            lines.append("  д\(day): \(parts.joined(separator: ", ")) · разом \(byReason.values.reduce(0, +))")
        }
        lines.append("")
        lines.append("— дії з 3+ сигналами —")
        for moment in moments where moment.signals.count >= 3 {
            lines.append("  д\(moment.day) \(moment.time) \(moment.action): \(moment.signals.joined(separator: "; "))")
        }
        lines.append("")
        lines.append("— усі дії —")
        for moment in moments {
            lines.append("  д\(moment.day) \(moment.time) \(moment.action): \(moment.signals.joined(separator: "; "))")
        }
        let moons = SkyCalendar.fullMoons(from: Self.date(day: 1, 0), to: Self.date(day: 8, 0))
        lines.append("повні в тижні: \(moons.count)")
        return lines.joined(separator: "\n")
    }

    private static func dayKey(_ day: Int) -> String {
        String(format: "2026-11-%02d", 1 + day)
    }

    private static func timeText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clockText(parts.hour ?? 0, parts.minute ?? 0)
    }
}
