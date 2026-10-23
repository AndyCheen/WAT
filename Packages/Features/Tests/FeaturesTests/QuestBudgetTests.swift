import XCTest
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

    private func assertBudget(_ simulation: FirstWeekSimulation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(simulation.days[0].dailyKeys, ["starter.firstGlass", "starter.halfGoal"], "день 1 — стартова пара",
                       file: file, line: line)
        XCTAssertFalse(simulation.days.flatMap(\.quests).isEmpty, "завдання за тиждень виконувались", file: file, line: line)
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
