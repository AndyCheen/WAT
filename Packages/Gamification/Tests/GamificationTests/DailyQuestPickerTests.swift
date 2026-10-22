import XCTest
import Core
import Persistence
@testable import Gamification

/// Щоденний пікер — SPEC-QUESTS §4. Чиста функція, тож перевіряється сотнями днів без бази.
final class DailyQuestPickerTests: XCTestCase {
    private let schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    private func input(day: Int = 0, dayNumber: Int = 10, seed: String = "1700000000000", level: Int = 6,
                       dayRhythm: Bool = true, reminders: Bool = true, issueMinute: Int = 8 * 60 + 15,
                       goalYesterday: Bool = true, goalDays7: Int = 7, yesterday: Set<String> = [],
                       recent: [String] = []) -> DailyPickInput {
        DailyPickInput(
            day: DayKey(ordinal: DayKey(rawValue: "2026-11-02").ordinal + day), dayNumber: dayNumber, seed: seed,
            level: level, dayRhythm: dayRhythm, remindersActive: reminders, schedule: schedule, goalMl: 2000,
            glassMl: 250, issueMinute: issueMinute, goalMetYesterday: goalYesterday, goalDays7: goalDays7,
            yesterdayKeys: yesterday, recentKeys: recent, weakBlock: WeakBlock(index: 1, median: 0.6)
        )
    }

    private func difficulty(_ picks: [QuestPick]) -> Int { picks.map(\.difficulty.rawValue).reduce(0, +) }

    func testSameInputSamePick() {
        for day in 0..<30 {
            XCTAssertEqual(DailyQuestPicker.pick(input(day: day)), DailyQuestPicker.pick(input(day: day)))
        }
        let a = (0..<30).map { DailyQuestPicker.pick(input(day: $0, seed: "a")).map(\.key) }
        let b = (0..<30).map { DailyQuestPicker.pick(input(day: $0, seed: "b")).map(\.key) }
        XCTAssertNotEqual(a, b, "зерно профілю міняє вибір")
    }

    func testPairPerSlotWithinBudget() {
        for day in 0..<200 {
            let picks = DailyQuestPicker.pick(input(day: day, seed: "\(day * 7919)"))
            XCTAssertEqual(picks.count, 2)
            XCTAssertEqual(QuestCatalog.definition(picks[0].key)?.slot, .tempo)
            XCTAssertEqual(QuestCatalog.definition(picks[1].key)?.slot, .rhythm)
            XCTAssertLessThanOrEqual(difficulty(picks), 4)
            for pick in picks {
                XCTAssertEqual(pick.rewardXp, XPRules.default.questXp(scope: .daily, difficulty: pick.difficulty))
            }
        }
    }

    /// Після дня без норми — лише легкі, сума ≤ 2 (§4.3).
    func testGentleAfterDayWithoutGoal() {
        for day in 0..<200 {
            let picks = DailyQuestPicker.pick(input(day: day, seed: "\(day)", goalYesterday: false))
            XCTAssertTrue(picks.allSatisfy { $0.difficulty == .easy }, "\(picks)")
            XCTAssertLessThanOrEqual(difficulty(picks), 2)
        }
    }

    /// Складні — лише з ≥ 5 днями норми з 7.
    func testHardNeedsFiveGoalDays() {
        let few = (0..<200).flatMap { DailyQuestPicker.pick(input(day: $0, seed: "\($0)", goalDays7: 4)) }
        XCTAssertFalse(few.contains { $0.difficulty == .hard })
        let many = (0..<200).flatMap { DailyQuestPicker.pick(input(day: $0, seed: "\($0)", goalDays7: 5)) }
        XCTAssertTrue(many.contains { $0.difficulty == .hard })
    }

    /// Без «Ритму дня» — одне з «Темпу» ∪ {Д5, Д6, Д10}.
    func testSingleWithoutDayRhythm() {
        let pool: Set<String> = ["daily.quarterBy", "daily.halfBy", "daily.threeQuartersBy", "daily.goalBy",
                                 "daily.goalNoReminders", "daily.wakeGlass", "daily.glasses", "daily.glassesBy"]
        for day in 0..<200 {
            let picks = DailyQuestPicker.pick(input(day: day, seed: "\(day)", dayRhythm: false))
            XCTAssertEqual(picks.count, 1)
            XCTAssertTrue(pool.contains(picks[0].key), picks[0].key)
        }
    }

    /// Без нагадувань — без Д4; рівень < 5 — без Д4 і Д9.
    func testRequirements() {
        let noReminders = (0..<300).flatMap { DailyQuestPicker.pick(input(day: $0, seed: "\($0)", reminders: false)) }
        XCTAssertFalse(noReminders.contains { $0.key == "daily.goalNoReminders" })
        XCTAssertTrue(noReminders.contains { $0.key == "daily.allBlocks" })
        let low = (0..<300).flatMap { DailyQuestPicker.pick(input(day: $0, seed: "\($0)", level: 4)) }
        XCTAssertFalse(low.contains { $0.key == "daily.goalNoReminders" || $0.key == "daily.allBlocks" })
    }

    func testNeverYesterdays() {
        for day in 0..<100 {
            let first = DailyQuestPicker.pick(input(day: day, seed: "\(day)"))
            let next = DailyQuestPicker.pick(input(day: day + 1, seed: "\(day)", yesterday: Set(first.map(\.key))))
            XCTAssertTrue(Set(next.map(\.key)).isDisjoint(with: first.map(\.key)))
        }
    }

    /// До дедлайну після видачі — щонайменше година (Д5 — 20 хв); T фіксується на інстансі.
    func testDeadlineNeedsLead() {
        for issue in stride(from: 8 * 60, through: 20 * 60, by: 30) {
            for day in 0..<40 {
                for pick in DailyQuestPicker.pick(input(day: day, seed: "\(day)", issueMinute: issue)) {
                    guard let deadline = pick.deadlineMinute else { continue }
                    let lead = QuestCatalog.definition(pick.key)!.minLeadMinutes
                    XCTAssertGreaterThanOrEqual(deadline - issue, lead, "\(pick.key) о \(issue)")
                }
            }
        }
        let late = (0..<100).flatMap { DailyQuestPicker.pick(input(day: $0, seed: "\($0)", issueMinute: 15 * 60)) }
        XCTAssertFalse(late.contains { ["daily.quarterBy", "daily.halfBy", "daily.wakeGlass"].contains($0.key) })
    }

    /// Стартові дні (§3.3).
    func testStarterDays() {
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 1)).map(\.key), ["starter.firstGlass", "starter.halfGoal"])
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 1, issueMinute: 18 * 60 + 30)).map(\.key),
                       ["starter.firstGlass"], "день почався пізніше за Z − 4 год")
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 1, dayRhythm: false)).map(\.key), ["starter.firstGlass"])
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 1, yesterday: ["starter.firstGlass"])).count, 2,
                       "хто вчора нічого не записав — знову день 1")

        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 2)).map(\.key), ["daily.wakeGlass", "starter.firstGoal"])
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 2, issueMinute: 10 * 60)).map(\.key),
                       ["daily.glasses", "starter.firstGoal"], "дедлайн Д5 минув — Д6")
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 2, dayRhythm: false)).map(\.key), ["starter.firstGoal"])
        XCTAssertEqual(DailyQuestPicker.pick(input(dayNumber: 2)).map(\.rewardXp), [15, 25])
    }

    // MARK: - Ротація (§4.7)

    private struct Person {
        let name: String
        var level = 6
        var dayRhythm = true
        var reminders = true
        /// Дні тижня (0 — пн) без норми.
        var missed: Set<Int> = []
    }

    /// 12 тижнів × 4 типи людей: правило «≤ 2 за 7 днів» не ламається, а повтор — у середньому не частіше ніж
    /// раз на 4 дні (без «Ритму дня» — раз на 6). Три зерна профілю на кожного.
    func testRotationOverTwelveWeeks() {
        let people = [
            Person(name: "сильний"),
            Person(name: "середній", level: 3, missed: [2, 6]),
            Person(name: "без ритму", dayRhythm: false, missed: [5]),
            Person(name: "без нагадувань", reminders: false, missed: [3])
        ]
        for person in people {
            for seed in ["1700000000000", "1731000000123", "1699999999999"] {
                var history: [[String]] = []
                for day in 0..<84 {
                    let goalYesterday = day == 0 || !person.missed.contains((day - 1) % 7)
                    let last7 = (1...7).map { day - $0 }.filter { $0 >= 0 }
                    let goalDays7 = last7.filter { !person.missed.contains($0 % 7) }.count + (7 - last7.count)
                    let picks = DailyQuestPicker.pick(input(
                        day: day, seed: seed, level: person.level, dayRhythm: person.dayRhythm,
                        reminders: person.reminders, goalYesterday: goalYesterday, goalDays7: goalDays7,
                        yesterday: Set(history.last ?? []),
                        recent: history.suffix(DailyQuestPicker.recentDays).flatMap { $0 }
                    ))
                    // На легкому дні слот може лишитись порожнім: правило повторів там не знімається.
                    let expected = !person.dayRhythm ? 1...1 : (goalYesterday ? 2...2 : 1...2)
                    XCTAssertTrue(expected.contains(picks.count), "\(person.name), день \(day): \(picks.map(\.key))")
                    history.append(picks.map(\.key))
                }
                check(history, person: person, seed: seed)
            }
        }
    }

    private func check(_ history: [[String]], person: Person, seed: String) {
        var days: [String: [Int]] = [:]
        for (day, keys) in history.enumerated() {
            for key in keys { days[key, default: []].append(day) }
        }
        var gaps: [Int] = []
        for (key, list) in days {
            for (index, day) in list.enumerated() {
                let inWeek = list[index...].prefix { $0 < day + 7 }.count
                XCTAssertLessThanOrEqual(inWeek, 2, "\(person.name) \(seed): \(key) з дня \(day)")
            }
            gaps += zip(list.dropFirst(), list).map { $0 - $1 }
        }
        let average = Double(gaps.reduce(0, +)) / Double(max(1, gaps.count))
        XCTAssertGreaterThanOrEqual(average, person.dayRhythm ? 4 : 6, "\(person.name) \(seed)")
    }
}
