import XCTest
import Core
import Persistence
@testable import Gamification

/// Адаптивні завдання на поведінці (WAT-67): 8 тижнів пікер → день людини → результат → наступний пікер, без бази.
/// Люди тут свої звички не змінюють — тест міряє, чи завдання підлаштовуються під них, а не навпаки. Аудит 60 днів
/// до WAT-67: «Три частини з трьох» 0 з 14, «5 склянок» у того, хто п'є 2–4 рази, 0 з 17, «Норма до T» у того, хто
/// закриває норму щодня, 0 з 12.
final class AdaptiveQuestSimulationTests: XCTestCase {
    private struct Person {
        let name: String
        var schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
        /// Порції дня: хвилина й об'єм; `day` — щоб звички трохи гуляли.
        let portions: (_ day: Int) -> [TimedPortion]
        /// Норму закрито раніше за будь-яке нагадування.
        var goalAhead = false
    }

    private static func jitter(_ day: Int, _ index: Int) -> Int { Int(StableHash.fnv1a("\(day)|\(index)") % 31) - 15 }

    /// Природна мінливість: день на порцію більший (30 %) чи менший (20 %) — без неї «на склянку більше, ніж
    /// зазвичай» було б недосяжним для будь-кого, хто п'є однаково, і тест міряв би статуї, а не людей.
    private static func varied(_ portions: [TimedPortion], day: Int, schedule: DaySchedule) -> [TimedPortion] {
        var result = portions
        let roll = Int(StableHash.fnv1a("vary|\(day)") % 100)
        if roll < 20, !result.isEmpty {
            result.remove(at: Int(StableHash.fnv1a("drop|\(day)") % UInt64(result.count)))
        } else if roll >= 70 {
            let span = UInt64(max(1, schedule.sleepMinutes - 60 - schedule.wakeMinutes))
            let minute = schedule.wakeMinutes + Int(StableHash.fnv1a("add|\(day)") % span)
            result.append(TimedPortion(minute: minute, ml: result.first?.ml ?? 250))
        }
        return result
    }

    private let people: [Person] = [
        Person(name: "рівно 8 × 250", portions: { day in
            [490, 590, 680, 770, 870, 960, 1060, 1160].enumerated().map {
                TimedPortion(minute: $0.element + jitter(day, $0.offset), ml: 250)
            }
        }, goalAhead: true),
        Person(name: "великими ковтками", portions: { day in
            [600, 870, 1140].enumerated().map { TimedPortion(minute: $0.element + jitter(day, $0.offset), ml: 700) }
        }),
        Person(name: "сова з графіком 10:30–24:00", schedule: DaySchedule(wakeMinutes: 10 * 60 + 30, sleepMinutes: 24 * 60),
               portions: { day in
            (0..<7).map { TimedPortion(minute: 660 + $0 * 120 + jitter(day, $0), ml: 300) }
        }),
        Person(name: "недобирає 1500", portions: { day in
            (0..<6).map { TimedPortion(minute: 540 + $0 * 120 + jitter(day, $0), ml: 250) }
        }),
        Person(name: "дрібно 10 × 200", portions: { day in
            (0..<10).map { TimedPortion(minute: 500 + $0 * 70 + jitter(day, $0), ml: 200) }
        })
    ]

    private let start = DayKey(rawValue: "2026-11-02")

    func testIssuedQuestsStayAchievable() {
        for person in people {
            var days: [QuestDay] = []
            var outcomes: [QuestOutcome] = []
            var issued: [[String]] = []
            var stats: [String: (issued: Int, done: Int)] = [:]

            for index in 0..<56 {
                let dayKey = DayKey(ordinal: start.ordinal + index)
                let portions = Self.varied(person.portions(index), day: index, schedule: person.schedule)
                let history = QuestHistory(today: dayKey, firstActive: start, days: days)
                let todayShape = QuestDay(day: dayKey, goalMl: 2000, schedule: person.schedule, portions: [])
                let input = DailyPickInput(
                    day: dayKey, dayNumber: index + 1, seed: "1700000000000", level: 6, dayRhythm: true,
                    remindersActive: true, schedule: person.schedule, goalMl: 2000, glassMl: 250,
                    issueMinute: portions.map(\.minute).min() ?? person.schedule.wakeMinutes,
                    goalMetYesterday: history.goalMetYesterday, goalDays7: history.goalDays(7),
                    yesterdayKeys: Set(issued.last ?? []), recentKeys: issued.suffix(DailyQuestPicker.recentDays).flatMap { $0 },
                    goalMedianMinute: history.goalMedianMinute, weakSpots: history.weakSpots(today: person.schedule),
                    weakBlock: history.weakBlock(blockCount: todayShape.blocks.count, seed: "1700000000000"),
                    baseline: index == 0 ? .none : history.baseline(), outcomes: outcomes
                )
                let picks = DailyQuestPicker.pick(input)
                let day = QuestDay(day: dayKey, goalMl: 2000, schedule: person.schedule, portions: portions,
                                   goalAhead: person.goalAhead && portions.reduce(0) { $0 + $1.ml } >= 2000)
                for pick in picks {
                    guard let condition = QuestCatalog.definition(pick.key)?.condition.dayCondition else { continue }
                    let params = QuestParams(deadlineMinute: pick.deadlineMinute, blockIndex: pick.blockIndex,
                                             count: pick.count, targetMl: pick.targetMl)
                    let done = condition.evaluate(on: day, params: params).met
                    outcomes.append(QuestOutcome(key: pick.key, day: dayKey, succeeded: done,
                                                 deadlineMinute: pick.deadlineMinute, count: pick.count,
                                                 targetMl: pick.targetMl))
                    var stat = stats[pick.key] ?? (0, 0)
                    stat.issued += 1
                    if done { stat.done += 1 }
                    stats[pick.key] = stat
                }
                issued.append(picks.map(\.key))
                days.append(day)
            }

            for (key, stat) in stats where stat.issued >= 5 && !key.hasPrefix("starter.") {
                XCTAssertGreaterThanOrEqual(Double(stat.done) / Double(stat.issued), 0.25,
                                            "\(person.name): \(key) — \(stat.done) з \(stat.issued)")
            }
            let total = stats.values.reduce((0, 0)) { ($0.0 + $1.issued, $0.1 + $1.done) }
            if ProcessInfo.processInfo.environment["WT_AUDIT"] == "1" {
                print("\(person.name): \(total.1)/\(total.0) — " + stats.sorted { $0.key < $1.key }
                    .map { "\($0.key.replacingOccurrences(of: "daily.", with: "")) \($0.value.done)/\($0.value.issued)" }
                    .joined(separator: ", "))
            }
            let share = Double(total.1) / Double(max(1, total.0))
            XCTAssertGreaterThanOrEqual(share, 0.4, "\(person.name): усього \(total.1) з \(total.0) — \(stats)")
            XCTAssertLessThanOrEqual(share, 0.95, "\(person.name): завдання мають і кликати вперед — \(stats)")
        }
    }
}
