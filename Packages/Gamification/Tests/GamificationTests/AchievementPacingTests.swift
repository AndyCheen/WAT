import XCTest
import Core
import Persistence
@testable import Gamification

/// Досягнення рідкісні й помітні не лише в перший тиждень (WAT-67): 60 днів людини, що п'є норму щодня рівно,
/// 8 × 250 мл, — стрес-тест каталогу. Аудит до WAT-67: день 10 — 6 досягнень, день 30 — 5, тиждень 2 — 13; «Нові
/// досягнення: 4» — сітка замість свята кожного. Перший тиждень тримає `AchievementBudgetTests` (Features).
@MainActor
final class AchievementPacingTests: XCTestCase {
    /// З другого тижня: не більше за день і за тиждень. Стрес-тест: звичайна людина відкриває помітно менше.
    static let maxPerDay = 3
    static let maxPerWeek = 10

    func testSixtyDiligentDays() {
        let env = GameEnv(day: 1, hour: 7, quests: nil)
        let start = DayKey(rawValue: "2026-11-02")
        let minutes = [490, 590, 680, 770, 870, 960, 1060, 1160]
        for index in 0..<60 {
            let key = DayKey(ordinal: start.ordinal + index).rawValue
            env.clock.set(GameEnv.date(key, hour: 7))
            env.game.refresh(at: env.clock.now)
            for minute in minutes {
                env.clock.set(GameEnv.date(key, hour: minute / 60, minute: minute % 60))
                env.drink(250, on: key, hour: minute / 60, minute: minute % 60)
            }
        }

        var perDay: [Int: [String]] = [:]
        for progress in env.store.allAchievementProgress() {
            guard let at = progress.unlockedAt else { continue }
            let day = env.calendar.dayKey(for: at).ordinal - start.ordinal + 1
            perDay[day, default: []].append(progress.defKey)
        }
        if ProcessInfo.processInfo.environment["WT_AUDIT"] == "1" {
            for day in perDay.keys.sorted() { print("д\(day): \(perDay[day]!.sorted())") }
        }
        for (day, keys) in perDay where day >= 8 {
            XCTAssertLessThanOrEqual(keys.count, Self.maxPerDay, "день \(day): \(keys.sorted())")
        }
        for week in 2...9 {
            let keys = ((week - 1) * 7 + 1...week * 7).flatMap { perDay[$0] ?? [] }
            XCTAssertLessThanOrEqual(keys.count, Self.maxPerWeek, "тиждень \(week): \(keys.sorted())")
        }
    }
}
