import XCTest
import Core
import Metrics
@testable import Gamification

@MainActor
final class PerformanceTests: XCTestCase {
    /// Сценарій сідера: багато порцій підряд. Тут ловимо квадратичну складність
    /// у нарахуванні XP і перерахунку серій.
    func testBulkIntakeThroughput() {
        let env = GameEnv()
        let start = Date()
        for index in 0..<200 {
            env.addIntakeEvent(200, hour: 8 + index % 12, day: 1 + index % 18)
        }
        let elapsed = Date().timeIntervalSince(start)
        print("⏱ 200 порцій за \(String(format: "%.2f", elapsed)) с")
        XCTAssertLessThan(elapsed, 4, "200 записів мають опрацьовуватись швидше за 4 с")
    }
}
