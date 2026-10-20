import XCTest
@testable import Features

/// Бюджет досягнень першого тижня (WAT-60, SPEC-ACHIEVEMENTS-CATALOG §10.4) — постійна перевірка на тижні
/// `FirstWeekSimulation`. Досягнення — свято, а не шум: у перший день без свідомих дій 1–2, за тиждень не більше
/// 6 у типового новачка й 8 у старанного. Нове досягнення, що відкривається в тиждень 1 без свідомої дії, ламає
/// цей тест — це сигнал переглянути поріг, а не підняти межу.
@MainActor
final class AchievementBudgetTests: XCTestCase {

    func testTypicalNewcomer() async {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.typicalWeek)
        await simulation.run()
        assertBudget(simulation, firstDay: 2, week: 6)
    }

    /// Норма щодня, рівно в ціль, рівномірно — стрес-тест каталогу без «Відкриттів».
    func testDiligentNewcomer() async {
        let simulation = FirstWeekSimulation(FirstWeekSimulation.diligentWeek())
        await simulation.run()
        assertBudget(simulation, firstDay: 2, week: 8)
    }

    private func assertBudget(_ simulation: FirstWeekSimulation, firstDay: Int, week: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        let days = simulation.days.map(\.achievements)
        XCTAssertLessThanOrEqual(days[0].count, firstDay, "день 1: \(days[0])", file: file, line: line)
        let all = days.flatMap { $0 }
        XCTAssertLessThanOrEqual(all.count, week, "тиждень: \(all)", file: file, line: line)
        // Одна дія — одне свято: досягнення дії складаються в один тост (після WAT-60 §2 — у одне вікно).
        for moment in simulation.moments {
            let announcements = moment.signals.filter { $0.hasPrefix("тост") && $0.contains("🏅") }
            XCTAssertLessThanOrEqual(announcements.count, 1, "д\(moment.day) \(moment.time): \(announcements)",
                                     file: file, line: line)
        }
    }
}
