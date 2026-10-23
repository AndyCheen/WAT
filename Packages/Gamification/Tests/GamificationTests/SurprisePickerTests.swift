import XCTest
import Core
import Persistence
@testable import Gamification

/// Пікер несподіваних — SPEC-QUESTS §6.1–6.3. Чиста функція: тижні симулюються без бази.
final class SurprisePickerTests: XCTestCase {
    private let schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)
    private var blocks: [GoalBlock] { schedule.curve(goalMl: 2000).goalBlocks() }
    /// Понеділок.
    private let start = DayKey(rawValue: "2026-11-02")

    private func input(day: DayKey, dayNumber: Int = 30, perWeek: Int = 2, signals: SurpriseSignals,
                       history: [SurpriseRecord] = [], issueMinute: Int = 8 * 60 + 5, quiet: [Range<Int>] = [],
                       dailyKeys: [String] = [], dailyBlock: Int? = nil, goalMet: Bool = false,
                       dayRhythm: Bool = true, seed: String = "1700000000000") -> SurprisePickInput {
        let calendar = CalendarService(clock: FixedClock(now: Date(timeIntervalSince1970: 0)))
        let week = calendar.weekKey(for: calendar.date(from: day))
        return SurprisePickInput(
            day: day, week: week, dayNumber: dayNumber, seed: seed, perWeek: perWeek, dayRhythm: dayRhythm,
            schedule: schedule, goalMl: 2000, issueMinute: issueMinute, goalMetToday: goalMet, history: history,
            signals: signals, quietMinutes: quiet, dailyKeys: dailyKeys, dailyBlockIndex: dailyBlock
        )
    }

    private func day(_ offset: Int) -> DayKey { DayKey(ordinal: start.ordinal + offset) }

    /// Перший день-кандидат цього тижня від хеша — щоб перевіряти вид, а не вгадувати день.
    private func candidate(week: Int = 0, signals: SurpriseSignals, perWeek: Int = 2) -> DayKey {
        let probe = input(day: day(7 * week), perWeek: perWeek, signals: signals)
        return day(7 * week + SurprisePicker.candidateDays(probe, limit: perWeek)[0])
    }

    /// Тижні поспіль: кожне видане несподіване лягає в історію з `state`.
    private func simulate(weeks: Int, perWeek: Int = 2, signals: SurpriseSignals, seed: String = "1700000000000",
                          state: QuestState = .completed) -> [(DayKey, QuestPick)] {
        var history: [SurpriseRecord] = []
        var picks: [(DayKey, QuestPick)] = []
        for offset in 0..<(7 * weeks) {
            let today = day(offset)
            guard let pick = SurprisePicker.pick(input(day: today, perWeek: perWeek, signals: signals,
                                                       history: history, seed: seed)) else { continue }
            picks.append((today, pick))
            history.append(SurpriseRecord(day: today, key: pick.key, state: state, blockIndex: pick.blockIndex))
        }
        return picks
    }

    private var weakEvening: SurpriseSignals { SurpriseSignals(weakPartKey: blocks.last!.deadlinePart.key) }

    // MARK: - Коли можна (§6.1)

    func testNotBeforeDayEight() {
        for offset in 0..<14 {
            for dayNumber in 1..<SurpriseRules.firstDay {
                XCTAssertNil(SurprisePicker.pick(input(day: day(offset), dayNumber: dayNumber, signals: weakEvening)))
            }
        }
    }

    func testWeeklyLimitsAndNeverTwoDaysInARow() {
        XCTAssertTrue(simulate(weeks: 8, perWeek: 0, signals: weakEvening).isEmpty, "вимкнено")
        for perWeek in 1...2 {
            for seed in ["a", "b", "c", "d", "e"] {
                let picks = simulate(weeks: 8, perWeek: perWeek, signals: weakEvening, seed: seed)
                let byWeek = Dictionary(grouping: picks) { ($0.0.ordinal - start.ordinal) / 7 }
                // Тиждень може випасти: кандидат у понеділок одразу після недільного — «не поспіль».
                XCTAssertGreaterThanOrEqual(byWeek.count, 6, "\(picks.map(\.0.rawValue))")
                XCTAssertTrue(byWeek.values.allSatisfy { $0.count <= perWeek }, "\(perWeek): \(byWeek.mapValues(\.count))")
                for (a, b) in zip(picks, picks.dropFirst()) {
                    XCTAssertGreaterThan(b.0.ordinal - a.0.ordinal, 1, "не два дні поспіль")
                }
            }
        }
        let two = simulate(weeks: 8, perWeek: 2, signals: weakEvening)
        XCTAssertGreaterThanOrEqual(two.count, 13, "здебільшого по два")
    }

    func testClosedGoalOrLateFirstActionGivesNothing() {
        let today = candidate(signals: weakEvening)
        XCTAssertNotNil(SurprisePicker.pick(input(day: today, signals: weakEvening)))
        XCTAssertNil(SurprisePicker.pick(input(day: today, signals: weakEvening, goalMet: true)))

        let start = SurprisePicker.pick(input(day: today, signals: weakEvening))!.startMinute!
        XCTAssertNotNil(SurprisePicker.pick(input(day: today, signals: weakEvening, issueMinute: start - 15)))
        XCTAssertNil(SurprisePicker.pick(input(day: today, signals: weakEvening, issueMinute: start - 14)),
                     "перша дія пізніше за хвилину − 15: людина отримує нагадування, а не несподіванку")
    }

    /// Два проігноровані поспіль — раз на 14 днів, доки одне не виконано (§6.1).
    func testBackoffAfterTwoIgnoredAndRecoveryAfterDone() {
        let ignored = simulate(weeks: 6, perWeek: 2, signals: weakEvening, state: .expired)
        XCTAssertEqual(ignored.count, 4, "два, потім по одному на 14 днів: \(ignored.map(\.0.rawValue))")
        for (a, b) in zip(ignored.dropFirst(), ignored.dropFirst(2)) {
            XCTAssertGreaterThanOrEqual(b.0.ordinal - a.0.ordinal, 14)
        }

        let today = candidate(week: 3, signals: weakEvening)
        let twoIgnored = [SurpriseRecord(day: day(14), key: "surprise.glassNow", state: .expired),
                          SurpriseRecord(day: day(16), key: "surprise.glassNow", state: .expired)]
        XCTAssertNil(SurprisePicker.pick(input(day: today, signals: weakEvening, history: twoIgnored)))
        let recovered = twoIgnored + [SurpriseRecord(day: day(18), key: "surprise.glassNow", state: .completed)]
        XCTAssertNotNil(SurprisePicker.pick(input(day: today, signals: weakEvening, history: recovered)))

        let cancelled = twoIgnored.map { SurpriseRecord(day: $0.day, key: $0.key, state: .cancelled) }
        XCTAssertNotNil(SurprisePicker.pick(input(day: today, signals: weakEvening, history: cancelled)),
                        "скасоване до появи — не проігноровано")
    }

    // MARK: - Вид (§6.2)

    func testWithoutGapsOnlyFlashOncePerWeek() {
        for seed in ["a", "b", "c"] {
            let picks = simulate(weeks: 8, perWeek: 2, signals: .none, seed: seed)
            let weeks = Set(picks.map { ($0.0.ordinal - start.ordinal) / 7 })
            XCTAssertEqual(weeks.count, picks.count, "не більше одного на тиждень")
            XCTAssertGreaterThanOrEqual(picks.count, 6)
            XCTAssertTrue(picks.allSatisfy { $0.1.key == "surprise.flash" })
            for (_, pick) in picks {
                XCTAssertEqual(pick.deadlineMinute! - pick.startMinute!, 15)
                XCTAssertGreaterThanOrEqual(pick.startMinute!, 10 * 60, "не раніше W + 2 год")
                XCTAssertLessThanOrEqual(pick.startMinute!, 19 * 60, "не пізніше Z − 3 год")
                XCTAssertEqual(pick.startMinute! % 5, 0)
                XCTAssertEqual(pick.rewardXp, 25)
            }
        }
    }

    func testWeakWeekdayGivesWeekdayGoalOnThatDay() {
        let saturday = SurpriseSignals(weakWeekday: 5)
        let pick = SurprisePicker.pick(input(day: day(5), signals: saturday))
        XCTAssertEqual(pick?.key, "surprise.weekday")
        XCTAssertEqual(pick?.weekdayIndex, 5)
        XCTAssertEqual(pick?.startMinute, 9 * 60, "W + 60")
        XCTAssertEqual(pick?.deadlineMinute, 20 * 60, "до Z − 2 год")
        XCTAssertEqual(pick?.rewardXp, 50)

        XCTAssertNil(SurprisePicker.pick(input(day: day(5), signals: saturday, dailyKeys: ["daily.goalBy"])),
                     "«Норма до {T}» сьогодні — несподіваного немає")
        let others = simulate(weeks: 4, signals: saturday).filter { $0.0.weekdayIndex != 5 }
        XCTAssertTrue(others.isEmpty, "лише слабкий день тижня — в інші дні тригера немає: \(others.map(\.1.key))")
    }

    func testWeakPartGivesGlassNowThenCloseBlock() {
        let today = candidate(week: 4, signals: weakEvening)
        let evening = blocks.count - 1
        let glass = SurprisePicker.pick(input(day: today, signals: weakEvening))
        XCTAssertEqual(glass?.key, "surprise.glassNow")
        XCTAssertEqual(glass?.blockIndex, evening)
        XCTAssertEqual(glass?.startMinute, blocks[evening].fromMinute + 30)
        XCTAssertEqual(glass?.deadlineMinute, blocks[evening].fromMinute + 90)
        XCTAssertEqual(glass?.rewardXp, 25)

        let done = [day(7), day(14)].map {
            SurpriseRecord(day: $0, key: "surprise.glassNow", state: .completed, blockIndex: evening)
        }
        let close = SurprisePicker.pick(input(day: today, signals: weakEvening, history: done))
        XCTAssertEqual(close?.key, "surprise.closeBlock", "≥ 2 виконаних Н1 у цій частині — Н2")
        XCTAssertEqual(close?.startMinute, blocks[evening].fromMinute)
        XCTAssertEqual(close?.deadlineMinute, 20 * 60, "кінець блоку — не пізніше Z − 2 год")
        XCTAssertEqual(close?.rewardXp, 50)

        XCTAssertEqual(SurprisePicker.pick(input(day: today, signals: weakEvening, history: done,
                                                 dailyKeys: ["daily.closeBlock"], dailyBlock: evening))?.key,
                       "surprise.glassNow", "Д7 на той самий блок — Н1")
        XCTAssertEqual(SurprisePicker.pick(input(day: today, signals: weakEvening, history: done, dayRhythm: false))?.key,
                       "surprise.glassNow", "без «Ритму дня» Н2 не називає частину доби")
    }

    // MARK: - Хвилина (§6.3)

    func testQuietPeriodShiftsOrCancels() {
        let today = candidate(week: 4, signals: weakEvening)
        let nominal = SurprisePicker.pick(input(day: today, signals: weakEvening))!.startMinute!
        let shifted = SurprisePicker.pick(input(day: today, signals: weakEvening, quiet: [(nominal - 10)..<(nominal + 20)]))
        XCTAssertEqual(shifted?.startMinute, nominal + 20, "зсув уперед до вільної хвилини")
        XCTAssertEqual(shifted?.deadlineMinute, nominal + 80, "вікно Н1 — та сама година")
        XCTAssertNil(SurprisePicker.pick(input(day: today, signals: weakEvening, quiet: [nominal..<(22 * 60)])),
                     "за межами — несподіваного немає")
    }

    func testWindowsStayInsideDayBounds() {
        for seed in (0..<40).map(String.init) {
            for signals in [weakEvening, .none, SurpriseSignals(weakPartKey: blocks[0].deadlinePart.key),
                            SurpriseSignals(weakWeekday: 2)] {
                for (_, pick) in simulate(weeks: 3, signals: signals, seed: seed) {
                    XCTAssertGreaterThanOrEqual(pick.startMinute!, 9 * 60, "не раніше W + 60")
                    XCTAssertLessThanOrEqual(pick.deadlineMinute!, 20 * 60, "кінець не пізніше Z − 2 год")
                    XCTAssertLessThan(pick.startMinute!, pick.deadlineMinute!)
                }
            }
        }
    }

    func testSameInputSamePick() {
        let today = candidate(signals: weakEvening)
        XCTAssertEqual(SurprisePicker.pick(input(day: today, signals: weakEvening)),
                       SurprisePicker.pick(input(day: today, signals: weakEvening)))
        let a = (0..<8).map { simulate(weeks: 1, signals: .none, seed: "a\($0)").map(\.0) }
        let b = (0..<8).map { simulate(weeks: 1, signals: .none, seed: "b\($0)").map(\.0) }
        XCTAssertNotEqual(a, b, "день — від зерна профілю")
    }
}
