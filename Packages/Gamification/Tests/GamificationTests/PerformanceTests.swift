import XCTest
import Core
import Metrics
import Persistence
@testable import Gamification

@MainActor
final class PerformanceTests: XCTestCase {
    /// Сценарій сідера: багато порцій підряд. Тут ловимо квадратичну складність
    /// у нарахуванні XP і перерахунку серій.
    func testBulkIntakeThroughput() {
        let env = GameEnv(quests: nil)
        let start = Date()
        for index in 0..<200 {
            env.addIntakeEvent(200, hour: 8 + index % 12, day: 1 + index % 18)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("⏱ 200 порцій за \(String(format: "%.2f", elapsed)) с")
        XCTAssertLessThan(elapsed, 4, "200 записів мають опрацьовуватись швидше за 4 с")
    }

    /// Те саме зі справжніми порціями в денних логах: XP за частину доби (§9) на кожну порцію
    /// читає порції дня — цей шлях не має повертати складність, яку прибрали кеші.
    func testBulkIntakeWithDayLogs() {
        let env = GameEnv(quests: nil)
        let start = Date()
        for index in 0..<200 {
            env.addIntake(200, hour: 8 + index % 12, day: 1 + index % 18)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("⏱ 200 порцій із логами за \(String(format: "%.2f", elapsed)) с")
        XCTAssertLessThan(elapsed, 4, "200 записів мають опрацьовуватись швидше за 4 с")
    }

    /// Правила досягнень ходять історією днів (WAT-24). Рік історії не має робити порцію помітно дорожчою:
    /// факти запам'ятовуються, а порція оновлює лише свій день.
    func testIntakeWithAYearOfHistory() {
        let env = GameEnv(quests: nil)
        env.clock.set(GameEnv.date("2027-07-18", hour: 14))
        for day in env.days(from: "2026-07-18", to: "2027-07-17") {
            let log = env.dayLogs.dayLog(for: DayKey(rawValue: day), goalMl: 2000, timeZoneId: "Europe/Kyiv")
            for hour in [9, 12, 15, 19] {
                env.dayLogs.insert(Intake(amountMl: 500, createdAt: GameEnv.date(day, hour: hour)), into: log)
            }
            log.totalMl = 2000
            log.countedMl = 2000
            log.entriesCount = 4
            log.partTotals = [0, 500, 500, 1000, 0]
        }
        env.dayLogs.save()
        env.game.refresh(at: env.clock.now)

        let start = Date()
        for index in 0..<50 {
            env.drink(200, on: "2027-07-18", hour: 8 + index % 12)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("⏱ 50 порцій з роком історії за \(String(format: "%.2f", elapsed)) с")
        XCTAssertLessThan(elapsed, 2, "рік історії: 50 порцій — швидше за 2 с")
    }
}
