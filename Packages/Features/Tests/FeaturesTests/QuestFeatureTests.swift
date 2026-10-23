import XCTest
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
@testable import Features

/// Тексти завдань (`QuestPresenter`) і вставки сповіщень на новому каталозі (SPEC-QUESTS §9.4).
@MainActor
final class QuestFeatureTests: XCTestCase {
    private func snapshot(_ key: String, deadline: Int? = nil, count: Int? = nil, block: Int? = nil,
                          progress: Double = 0, target: Double = 1, isDone: Bool = false) -> QuestSnapshot {
        let definition = QuestCatalog.definition(key)!
        return QuestSnapshot(id: UUID(), key: key, scope: definition.scope, slot: definition.slot, title: definition.title,
                             kind: definition.kind, progress: progress, target: target, isDone: isDone,
                             difficulty: .easy, rewardXp: 15, deadlineMinute: deadline, count: count, blockIndex: block,
                             blockCount: block == nil ? nil : 3)
    }

    func testTitles() {
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.halfBy", deadline: 14 * 60)), "Половина до 14:00")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.halfBy", deadline: 14 * 60), format: .hours12),
                       "Половина до 2:00 пп")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.glasses", count: 3)), "3 склянки від 150 мл")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.glasses", count: 5), unit: .usFluidOunces),
                       "5 склянок від 5 унц.")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.glassesBy", deadline: 13 * 60 + 30, count: 3)),
                       "3 склянки до 13:30")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.closeBlock", block: 0)), "Закрий ранок")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.closeBlock", block: 1)), "Закрий день")
        XCTAssertEqual(QuestPresenter.title(snapshot("daily.closeBlock", block: 2)), "Закрий вечір")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.goalDays", count: 4)), "Норма 4 дні")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.goalDays", count: 5)), "Норма 5 днів")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.goalRun", count: 3)), "Норма 3 дні поспіль")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.wakeGlassDays", count: 3)), "3 ранки зі склянкою")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.wakeGlassDays", count: 5)), "5 ранків зі склянкою")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.perfectDays", count: 2)), "2 ідеальні дні")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.perfectDays", count: 5)), "5 ідеальних днів")
        XCTAssertEqual(QuestPresenter.title(snapshot("weekly.halfByDays", count: 4)), "4 дні: половина до обіду")
    }

    /// Найгірші значення — 12 год, унції, N = 5 і 6 — вміщаються в рядок головного (≤ 28) і без роду (CLAUDE.md).
    func testWorstCaseTitlesFit() {
        let pastTense = ["пив", "пила", "випив", "випила", "закрив", "закрила", "виконав", "виконала"]
        for definition in QuestCatalog.active {
            for count in [3, 5, 6] {
                let quest = snapshot(definition.key, deadline: 12 * 60 + 30, count: count, block: 1)
                for unit in VolumeUnit.allCases {
                    let title = QuestPresenter.title(quest, unit: unit, format: .hours12)
                    XCTAssertLessThanOrEqual(title.count, 28, title)
                    let words = title.lowercased().split { !$0.isLetter }.map(String.init)
                    XCTAssertTrue(Set(words).isDisjoint(with: pastTense), title)
                }
            }
        }
    }

    func testProgressLabels() {
        XCTAssertEqual(QuestPresenter.progressLabel(snapshot("daily.halfBy", progress: 520, target: 1000)), "ще 500 мл")
        XCTAssertEqual(QuestPresenter.progressLabel(snapshot("daily.halfBy", progress: 510, target: 1000)), "ще 500 мл",
                       "вгору до 50")
        XCTAssertEqual(QuestPresenter.progressLabel(snapshot("daily.halfBy", progress: 700, target: 1000),
                                                    unit: .usFluidOunces), "ще 11 унц.")
        XCTAssertEqual(QuestPresenter.progressLabel(snapshot("daily.glasses", progress: 2, target: 4)), "2/4")
        XCTAssertEqual(QuestPresenter.progressLabel(snapshot("weekly.goalDays", progress: 2, target: 5)), "2/5 дн.")
        XCTAssertEqual(QuestPresenter.progressLabel(snapshot("weekly.goalDays", isDone: true)), "Готово")
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(QuestPresenter.accessibilityLabel(snapshot("daily.halfBy", deadline: 14 * 60, progress: 500,
                                                                  target: 1000), xp: 25),
                       "Половина до 14:00, ще 500 мл, 25 XP")
        XCTAssertEqual(QuestPresenter.accessibilityLabel(snapshot("daily.glasses", count: 4, progress: 2, target: 4), xp: 15),
                       "4 склянки від 150 мл, 2 з 4, 15 XP")
        XCTAssertEqual(QuestPresenter.accessibilityLabel(snapshot("weekly.goalDays", count: 5, progress: 2, target: 5), xp: 100),
                       "Норма 5 днів, 2 з 5 днів, 100 XP")
        XCTAssertEqual(QuestPresenter.accessibilityLabel(snapshot("daily.wakeGlass", isDone: true), xp: 30),
                       "Склянка після підйому, виконано, 30 XP")
    }

    func testSectionCaptions() {
        XCTAssertEqual(QuestPresenter.weekLabel + " " + QuestPresenter.weekDaysLeft(5), "ЦЬОГО ТИЖНЯ · ЩЕ 5 ДН.")
        XCTAssertEqual(QuestPresenter.completedToggle(count: 2, showing: false), "Виконані · 2")
        XCTAssertEqual(QuestPresenter.completedToggle(count: 2, showing: true), "Сховати")
    }

    // MARK: - Блок головного (§9.1)

    private func quest(_ key: String, done: Bool = false, deadline: Date? = nil) -> QuestSnapshot {
        let definition = QuestCatalog.definition(key)!
        return QuestSnapshot(id: UUID(), key: key, scope: definition.scope, slot: definition.slot, title: definition.title,
                             kind: definition.kind, progress: done ? 1 : 0, target: 1, isDone: done, difficulty: .easy,
                             rewardXp: 15, deadline: deadline)
    }

    func testBlockHidesDoneBehindToggleAndCelebrates() {
        let wake = quest("daily.wakeGlass", done: true, deadline: Self.date(8, 0))
        let glasses = quest("daily.glasses")
        let week = quest("weekly.goalDays")
        let board = QuestBoard(daily: [wake, glasses], weekly: [week], weekDaysLeft: 5)

        let block = QuestBlock.make(board: board, now: Self.date(9, 0), celebrating: [], showCompleted: false)
        XCTAssertEqual(block.today?.rows.map(\.key), ["daily.glasses"])
        XCTAssertNil(block.today?.empty)
        XCTAssertEqual(block.week?.rows.map(\.key), ["weekly.goalDays"])
        XCTAssertEqual(block.weekDaysLeft, 5)
        XCTAssertEqual(block.completedCount, 1, "виконане до дедлайну лишається у «Виконані»")

        let celebrating = QuestBlock.make(board: board, now: Self.date(9, 0), celebrating: [wake.id], showCompleted: false)
        XCTAssertEqual(celebrating.today?.rows.map(\.key), ["daily.wakeGlass", "daily.glasses"], "святкує — ще в списку")

        let shown = QuestBlock.make(board: board, now: Self.date(9, 0), celebrating: [], showCompleted: true)
        XCTAssertEqual(shown.today?.rows.count, 2, "«Виконані · N» розгортає виконані в їхніх секціях")
    }

    func testBlockEmptyStates() {
        let now = Self.date(15, 0)
        let doneA = quest("daily.halfBy", done: true), doneB = quest("daily.glasses", done: true)
        let allDone = QuestBlock.make(board: QuestBoard(daily: [doneA, doneB], weekly: [quest("weekly.goalDays", done: true)]),
                                      now: now, celebrating: [], showCompleted: false)
        XCTAssertEqual(allDone.today, QuestBlock.Section(rows: [], empty: "Усе на сьогодні 🎉"))
        XCTAssertEqual(allDone.week, QuestBlock.Section(rows: [], empty: "Тиждень закрито 🎉"))

        // Одне виконане, друге зникло за дедлайном — «усе» не кажемо, секції немає.
        let expired = QuestBlock.make(board: QuestBoard(daily: [doneA], expiredDaily: 1), now: now, celebrating: [],
                                      showCompleted: false)
        XCTAssertNil(expired.today)
        XCTAssertEqual(expired.completedCount, 1)
        XCTAssertFalse(expired.isEmpty, "заголовок із «Виконані · 1» лишається")

        // Дедлайн минув, поки екран відкритий: дошку ще не перечитано, а рядка вже немає.
        let late = QuestBlock.make(board: QuestBoard(daily: [quest("daily.wakeGlass", deadline: Self.date(8, 0))]),
                                   now: Self.date(8, 0), celebrating: [], showCompleted: false)
        XCTAssertNil(late.today)
        XCTAssertTrue(late.isEmpty)

        let friday = QuestBlock.make(board: QuestBoard(weeklyStartsMonday: true, weekDaysLeft: 3), now: now,
                                     celebrating: [], showCompleted: false)
        XCTAssertEqual(friday.week, QuestBlock.Section(rows: [], empty: "Тижневі завдання — з понеділка"))
        XCTAssertNil(friday.weekDaysLeft, "«ще N дн.» — лише коли тижневі є")
    }

    // MARK: - Свято на головному (§9.2)

    /// Перша порція відкриває «Першу краплю»: рядок святкує після вікна, вібрує вікно.
    func testRowCelebratesAfterAchievementWindow() {
        let (services, clock) = services(at: Self.date(7, 10), quests: QuestForcing(daily: ["daily.wakeGlass", "daily.glasses"]))
        let model = HomeViewModel(services: services)
        let wake = model.questBoard.daily.first { $0.key == "daily.wakeGlass" }!

        model.add(250)
        XCTAssertNotNil(services.celebration, "«Перша крапля»")
        XCTAssertEqual(model.pulse?.kind, .celebration, "одна вібрація на дію")
        XCTAssertEqual(model.pendingQuestIds, [wake.id])
        XCTAssertTrue(model.celebratingQuestIds.isEmpty, "під вікном рядок не святкує")
        XCTAssertEqual(model.questBlock().today?.rows.map(\.key), ["daily.wakeGlass", "daily.glasses"],
                       "і не зникає, щоб не з'явитися знову")

        services.dismissCelebration()
        model.celebrationDidClose()
        XCTAssertEqual(model.celebratingQuestIds, [wake.id])
        XCTAssertTrue(model.pendingQuestIds.isEmpty)

        model.finishQuestCelebration(wake.id)
        XCTAssertEqual(model.questBlock().today?.rows.map(\.key), ["daily.glasses"], "згорнуто в «Виконані · 1»")
        XCTAssertEqual(model.questBlock().completedCount, 1)

        // Дедлайн другого не минає — а прострочене зникло б без `reload()`.
        clock.set(Self.date(23, 59))
        XCTAssertEqual(model.questBlock().today?.rows.map(\.key), ["daily.glasses"])
    }

    /// Без вікна й без гучнішої події дія з виконаним завданням вібрує `questDone` і святкує одразу.
    func testRowCelebratesAtOnceWithQuestHaptic() {
        let (services, _) = services(at: Self.date(9, 0), quests: QuestForcing(daily: ["daily.glasses"]))
        let model = HomeViewModel(services: services)
        for _ in 0..<4 {
            model.add(200)
            if services.celebration != nil {
                services.dismissCelebration()
                model.celebrationDidClose()
            }
        }
        XCTAssertTrue(model.celebratingQuestIds.isEmpty)
        model.add(200)
        XCTAssertNil(services.celebration)
        XCTAssertEqual(model.pulse?.kind, .questDone)
        XCTAssertEqual(model.celebratingQuestIds.count, 1)
        XCTAssertNil(model.toast, "тостів за завдання немає")
    }

    // MARK: - Вставки сповіщень

    /// 19.10.2026 — понеділок.
    private static func date(day: Int = 19, _ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: parts)!
    }

    private func services(at date: Date, quests: QuestForcing) -> (AppServices, FixedClock) {
        let clock = FixedClock(now: date)
        let services = AppServices(container: Database.makeInMemoryContainer(), clock: clock,
                                   notificationCenter: InMemoryNotificationCenter())
        services.gamification.questForcing = quests
        services.bootstrap()
        return (services, clock)
    }

    func testMorningHintFollowsWakeGlass() {
        let (services, _) = services(at: Self.date(7, 30), quests: QuestForcing(daily: ["daily.wakeGlass"]))
        XCTAssertTrue(services.makeNotificationContext().quests.morningQuestActive)
        services.hydration.addIntake(amountMl: 250)
        XCTAssertFalse(services.makeNotificationContext().quests.morningQuestActive, "виконане — вже не підказка")
    }

    func testOneGlassLeftNamesTheQuest() {
        let (services, _) = services(at: Self.date(9, 0), quests: QuestForcing(daily: ["daily.glasses"]))
        for _ in 0..<3 { services.hydration.addIntake(amountMl: 250) }
        XCTAssertNil(services.makeNotificationContext().quests.oneEntryLeftTitle, "бракує двох")
        services.hydration.addIntake(amountMl: 250)
        XCTAssertEqual(services.makeNotificationContext().quests.oneEntryLeftTitle, "5 склянок від 150 мл")
    }

    func testSundayHintForWeeklyClosedByTodaysGoal() {
        let (services, clock) = services(at: Self.date(9, 0), quests: QuestForcing(weekly: [("weekly.goalDays", 2)]))
        services.hydration.addIntake(amountMl: 2000)
        clock.set(Self.date(day: 24, 10))
        XCTAssertNil(services.makeNotificationContext().quests.weeklyClosesToday, "субота — ще не неділя")

        clock.set(Self.date(day: 25, 10))
        services.handleBecameActive()
        let hint = services.makeNotificationContext().quests.weeklyClosesToday
        XCTAssertEqual(hint?.title, "Норма 2 дні")
        XCTAssertEqual(hint?.xp, 75)
    }

    // MARK: - Несподівані (WAT-65)

    private func surprise(_ key: String, from: Date, until: Date, weekday: Int? = nil, block: Int? = nil,
                          progress: Double = 0, target: Double = 250, isDone: Bool = false) -> QuestSnapshot {
        let definition = QuestCatalog.definition(key)!
        let minute = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Europe/Kyiv")!, from: until)
        return QuestSnapshot(id: UUID(), key: key, scope: .adhoc, slot: .surprise, title: definition.title, kind: .volume,
                             progress: progress, target: target, isDone: isDone, difficulty: .easy, rewardXp: 25,
                             deadline: until, deadlineMinute: minute.hour! * 60 + minute.minute!, blockIndex: block,
                             blockCount: block == nil ? nil : 3, visibleFrom: from, weekdayIndex: weekday)
    }

    func testSurpriseCardTexts() {
        let glass = surprise("surprise.glassNow", from: Self.date(13, 30), until: Self.date(14, 30), progress: 100)
        XCTAssertEqual(QuestPresenter.title(glass), "Склянка зараз")
        XCTAssertEqual(QuestPresenter.surpriseKind(glass), "НЕСПОДІВАНЕ")
        XCTAssertEqual(QuestPresenter.surpriseDetail(glass), "250 мл до 14:30 · ще 150 мл")
        XCTAssertEqual(QuestPresenter.surpriseDetail(glass, unit: .usFluidOunces, format: .hours12),
                       "8 унц. до 2:30 пп · ще 6 унц.", "вгору до цілої унції")
        XCTAssertEqual(QuestPresenter.surpriseReward(xp: 50), "+50 XP · ⚡")

        let flash = surprise("surprise.flash", from: Self.date(16, 10), until: Self.date(16, 25), target: 150)
        XCTAssertEqual(QuestPresenter.surpriseKind(flash), "БЛИСКАВКА")
        XCTAssertEqual(QuestPresenter.title(surprise("surprise.weekday", from: Self.date(9), until: Self.date(20),
                                                     weekday: 5)), "Субота з нормою")
        XCTAssertEqual(QuestPresenter.title(surprise("surprise.closeBlock", from: Self.date(17), until: Self.date(20),
                                                     block: 2)), "Закрий вечір до 20:00")
        let done = surprise("surprise.glassNow", from: Self.date(13, 30), until: Self.date(14, 30), isDone: true)
        XCTAssertEqual(QuestPresenter.surpriseDetail(done), "Готово · ⚡ у призах")
    }

    func testBlockShowsSurpriseOnlyInsideItsWindow() {
        let quest = surprise("surprise.glassNow", from: Self.date(13, 30), until: Self.date(14, 30))
        let board = QuestBoard(surprise: quest)
        XCTAssertTrue(QuestBlock.make(board: board, now: Self.date(13, 29), celebrating: [], showCompleted: false).isEmpty)
        XCTAssertEqual(QuestBlock.make(board: board, now: Self.date(13, 30), celebrating: [], showCompleted: false)
            .surprise?.id, quest.id)
        XCTAssertNil(QuestBlock.make(board: board, now: Self.date(14, 30), celebrating: [], showCompleted: false).surprise,
                     "прострочене зникає без сліду")

        let done = surprise("surprise.glassNow", from: Self.date(13, 30), until: Self.date(14, 30), isDone: true)
        let doneBoard = QuestBoard(surprise: done)
        let collapsed = QuestBlock.make(board: doneBoard, now: Self.date(15), celebrating: [], showCompleted: false)
        XCTAssertNil(collapsed.surprise)
        XCTAssertEqual(collapsed.completedCount, 1, "виконане — у «Виконані · N»")
        XCTAssertEqual(QuestBlock.make(board: doneBoard, now: Self.date(15), celebrating: [done.id],
                                       showCompleted: false).surprise?.id, done.id, "поки святкує")
    }

    /// Наперед — у контексті сповіщень і знімку віджета; після появи — лише на головному й у віджеті.
    func testSurpriseReachesNotificationsAndWidget() {
        let (services, clock) = services(at: Self.date(9, 0), quests: QuestForcing(surprise: ("surprise.flash", 16 * 60)))
        let slot = services.makeNotificationContext().surprise
        XCTAssertEqual(slot?.kind, .flash)
        XCTAssertEqual(slot?.fireAt, Self.date(16, 0))
        XCTAssertEqual(slot?.deadline, Self.date(16, 15))
        XCTAssertEqual(slot?.targetMl, 150)
        XCTAssertEqual(slot?.leftMl, 150)

        let widget = services.makeWidgetSnapshot(plan: services.notifications.lastPlan).surprise
        XCTAssertEqual(widget?.title, "Блискавка: 15 хвилин")
        XCTAssertEqual(widget?.visibleFrom, Self.date(16, 0))
        XCTAssertEqual(widget?.expiresAt, Self.date(16, 15))
        XCTAssertFalse(widget!.isOpen(at: Self.date(15, 59)))
        XCTAssertTrue(widget!.isOpen(at: Self.date(16, 1)))

        clock.set(Self.date(16, 5))
        XCTAssertNil(services.makeNotificationContext().surprise, "уже з'явилось — сповіщення не наздоганяє")
    }

    /// «Вимк» — сьогоднішнє зникає, «Несподіванка» замкнена з підписом гейта (§9.5).
    func testSettingOffCancelsTodayAndLocksAchievement() {
        let (services, _) = services(at: Self.date(9, 0), quests: QuestForcing(surprise: ("surprise.flash", 16 * 60)))
        let model = NotificationsSettingsModel(services: services)
        XCTAssertEqual(model.surprisePerWeek, 2, "типово — двічі на тиждень")
        XCTAssertNil(services.gamification.achievementSnapshots().first { $0.key == "quest.firstSurprise" }?.lockedCaption)

        model.selectSurprisePerWeek(0)
        XCTAssertEqual(services.profile.surpriseQuestsPerWeek, 0)
        XCTAssertNil(services.gamification.questBoard().surprise)
        XCTAssertNil(services.makeNotificationContext().surprise)
        XCTAssertEqual(services.gamification.achievementSnapshots().first { $0.key == "quest.firstSurprise" }?.lockedCaption,
                       "Увімкни несподівані завдання")

        model.selectSurprisePerWeek(1)
        XCTAssertEqual(model.surprisePerWeek, 1)
    }
}
