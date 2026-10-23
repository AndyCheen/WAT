import XCTest
import Core
import Persistence
import Notifications
@testable import Features

/// Бюджет уваги завдань у перший тиждень (SPEC-QUESTS §10, QUESTS-PLAN §2.7) — на тих самих тижнях
/// `FirstWeekSimulation`, що й бюджет досягнень: стартова пара в день 1, жодного тоста за завдання,
/// не більше двох щоденних на головному.
@MainActor
final class QuestBudgetTests: XCTestCase {
    func testTypicalNewcomer() async {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.typicalWeek)
        await simulation.run()
        assertBudget(simulation)
    }

    func testDiligentNewcomer() async {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.diligentWeek())
        await simulation.run()
        assertBudget(simulation)
    }

    func testExplorer() async {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.explorerWeek(), explorer: true)
        await simulation.run()
        assertBudget(simulation)
    }

    /// Людина з історією: з 8-го дня несподівані є, і щотижня їх не більше двох, ніколи два дні поспіль (§6.1).
    /// Вечір щодня провалений — прогалина частини доби, тож видається Н1.
    func testSurprisesFromDayEightAtMostTwoPerWeek() {
        let clock = FixedClock(now: Self.date(day: 2, 8), timeZone: FirstWeekSimulation.zone)
        let services = AppServices(container: Database.makeInMemoryContainer(), clock: clock,
                                   notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
        var issued: [(day: Int, key: String)] = []
        for day in 2...29 {
            clock.set(Self.date(day: day, 8, 30))
            services.handleBecameActive()
            if let surprise = services.gamification.questBoard().surprise { issued.append((day, surprise.key)) }
            for (hour, ml) in [(9, 600), (12, 500), (15, 500), (21, 100)] {
                clock.set(Self.date(day: day, hour))
                services.hydration.addIntake(amountMl: ml)
            }
        }
        XCTAssertTrue(issued.allSatisfy { $0.day >= 9 }, "день людини 8 — 9 листопада: \(issued)")
        XCTAssertFalse(issued.isEmpty)
        XCTAssertTrue(issued.allSatisfy { $0.key == "surprise.glassNow" }, "\(issued)")
        // Пн 2 листопада — початок тижня: тиждень = (день − 2) / 7.
        let perWeek = Dictionary(grouping: issued) { ($0.day - 2) / 7 }.mapValues(\.count)
        XCTAssertTrue(perWeek.values.allSatisfy { $0 <= 2 }, "\(perWeek)")
        for (a, b) in zip(issued, issued.dropFirst()) { XCTAssertGreaterThan(b.day - a.day, 1, "не поспіль") }
    }

    private static func date(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = FirstWeekSimulation.zone
        return calendar.date(from: parts)!
    }

    private func assertBudget(_ simulation: FirstWeekSimulation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(simulation.days[0].dailyKeys, ["starter.firstGlass", "starter.halfGoal"], "день 1 — стартова пара",
                       file: file, line: line)
        XCTAssertFalse(simulation.days.flatMap(\.quests).isEmpty, "завдання за тиждень виконувались", file: file, line: line)
        XCTAssertTrue(simulation.days.allSatisfy(\.surprises.isEmpty), "несподівані — з 8-го дня (§6.1)",
                      file: file, line: line)
        for (index, day) in simulation.days.enumerated() {
            XCTAssertLessThanOrEqual(day.maxDailyRows, 2, "день \(index + 1)", file: file, line: line)
            // Свято виконаного — у рядку (§9.2): у тостах ні назви завдання, ні слова про нього.
            let titles = day.quests
            for toast in day.homeToasts {
                XCTAssertFalse(toast.localizedCaseInsensitiveContains("завдання"), toast, file: file, line: line)
                XCTAssertFalse(titles.contains { toast.contains($0) }, toast, file: file, line: line)
            }
        }
    }
}
