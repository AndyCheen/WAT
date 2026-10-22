import XCTest
import Core
import Persistence
@testable import Gamification

/// Тижневий пікер — SPEC-QUESTS §5.
final class WeeklyQuestPickerTests: XCTestCase {
    private func input(today: Int = 0, firstWeek: Bool = false, seed: String = "1700000000000", level: Int = 6,
                       dayRhythm: Bool = true, weeks: [Int] = [5, 5, 5, 5], lastWeek: [(key: String, isDone: Bool)] = [],
                       goalDays14: Int = 10) -> WeeklyPickInput {
        WeeklyPickInput(week: WeekKey(rawValue: "2026-W45"), todayIndex: today, isFirstWeek: firstWeek, seed: seed,
                        level: level, dayRhythm: dayRhythm, goalDaysPerFullWeek: weeks, lastWeek: lastWeek,
                        goalDays14: goalDays14)
    }

    /// Лише Пн–Чт: до кінця тижня ≥ 4 дні разом із сьогоднішнім.
    func testIssuedMondayToThursday() {
        for today in 0...3 { XCTAssertEqual(WeeklyQuestPicker.pick(input(today: today)).count, 2, "день \(today)") }
        for today in 4...6 { XCTAssertTrue(WeeklyQuestPicker.pick(input(today: today)).isEmpty, "день \(today)") }
    }

    func testFirstWeekGetsOneEasy() {
        let picks = WeeklyQuestPicker.pick(input(today: 2, firstWeek: true))
        XCTAssertEqual(picks.map(\.key), ["weekly.goalDays"])
        XCTAssertEqual(picks.first?.count, 3)
        XCTAssertEqual(picks.first?.difficulty, .easy)
        XCTAssertEqual(picks.first?.rewardXp, 75)
    }

    /// N: медіана + 1, у межах 3…6; ±1 за минулий тиждень; завжди запасний день.
    func testGoalDaysCount() {
        let n = { (input: WeeklyPickInput) in WeeklyQuestPicker.goalDaysCount(input, spare: input.daysLeft - 1) }
        XCTAssertEqual(n(input(weeks: [3, 4, 4, 5])), 5)
        XCTAssertEqual(n(input(weeks: [])), 4, "без повних тижнів база — 3")
        XCTAssertEqual(n(input(weeks: [7, 7, 7, 7])), 6)
        XCTAssertEqual(n(input(weeks: [0, 0, 1, 0])), 3)
        XCTAssertEqual(n(input(weeks: [4, 4], lastWeek: [("weekly.goalDays", true), ("weekly.weekend", true)])), 6)
        XCTAssertEqual(n(input(weeks: [4, 4], lastWeek: [("weekly.goalDays", false), ("weekly.weekend", false)])), 4)
        XCTAssertEqual(n(input(weeks: [4, 4], lastWeek: [("weekly.goalDays", true), ("weekly.weekend", false)])), 5)
        XCTAssertEqual(n(input(today: 3, weeks: [7, 7, 7, 7])), 3, "у четвер — не більше 3: запасний день")
    }

    /// Кому важко (менше 6 днів норми за 14) — «Половина норми» на всі дні, крім запасного.
    func testHalfDaysForThoseWhoStruggle() {
        let picks = WeeklyQuestPicker.pick(input(today: 1, goalDays14: 5))
        XCTAssertEqual(picks.first?.key, "weekly.halfDays")
        XCTAssertEqual(picks.first?.count, 5)
        XCTAssertEqual(picks.first?.difficulty, .easy)
    }

    /// Т2 — N(Т1) − 2; менше 3 — не допущене.
    func testRunNeedsThree() {
        let low = (0..<100).compactMap { WeeklyQuestPicker.pick(input(seed: "\($0)", weeks: [2, 2, 2, 2])).first }
        XCTAssertFalse(low.contains { $0.key == "weekly.goalRun" })
        let high = (0..<100).compactMap { WeeklyQuestPicker.pick(input(seed: "\($0)", weeks: [6, 6, 6, 6])).first }
        let runs = high.filter { $0.key == "weekly.goalRun" }
        XCTAssertFalse(runs.isEmpty)
        XCTAssertTrue(runs.allSatisfy { $0.count == 4 && $0.difficulty == .hard })
        XCTAssertGreaterThan(high.filter { $0.key == "weekly.goalDays" }.count, runs.count, "Т1 — вага 2")
    }

    /// «Звичка» не повторює минулий тиждень; «Сталість» — лише якщо інакше нічого.
    func testNoRepeatOfLastWeek() {
        for seed in 0..<100 {
            let picks = WeeklyQuestPicker.pick(input(seed: "\(seed)", lastWeek: [("weekly.goalRun", true),
                                                                                  ("weekly.wakeGlassDays", true)]))
            XCTAssertEqual(picks.first?.key, "weekly.goalDays")
            XCTAssertNotEqual(picks.last?.key, "weekly.wakeGlassDays")
        }
    }

    /// N «Звички» — з таблиці, але не більше за дні, що лишились, мінус запасний. Т7 — лише з ритмом і з 5-го рівня.
    func testHabitCountsAndRequirements() {
        let habits = (0..<200).compactMap { WeeklyQuestPicker.pick(input(today: 2, seed: "\($0)")).last }
        for pick in habits {
            XCTAssertEqual(QuestCatalog.definition(pick.key)?.slot, .habit)
            XCTAssertLessThanOrEqual(pick.count ?? 0, 4, pick.key)
        }
        XCTAssertEqual(habits.first { $0.key == "weekly.weekend" }?.count, 2)
        XCTAssertTrue(habits.contains { $0.key == "weekly.perfectDays" })
        let plain = (0..<200).compactMap { WeeklyQuestPicker.pick(input(seed: "\($0)", dayRhythm: false)).last }
        XCTAssertFalse(plain.contains { $0.key == "weekly.perfectDays" })
        let low = (0..<200).compactMap { WeeklyQuestPicker.pick(input(seed: "\($0)", level: 3)).last }
        XCTAssertFalse(low.contains { $0.key == "weekly.perfectDays" })
    }
}
