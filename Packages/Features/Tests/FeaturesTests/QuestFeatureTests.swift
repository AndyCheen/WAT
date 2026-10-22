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
}
