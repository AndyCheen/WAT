import XCTest
import Core
import Persistence
@testable import Gamification

/// Адаптивні завдання (WAT-67, SPEC-QUESTS §12): ціль — від того, як людина зазвичай п'є, з кроком у бік ідеалу;
/// успіх піднімає планку, провал опускає, повторний провал — пауза.
final class QuestAdaptationTests: XCTestCase {
    private let today = DayKey(rawValue: "2026-11-16")
    private func day(_ back: Int) -> DayKey { DayKey(ordinal: today.ordinal - back) }

    // MARK: - Сходинки

    private func outcome(_ back: Int, _ succeeded: Bool, deadline: Int? = nil, count: Int? = nil,
                         target: Int? = nil) -> QuestOutcome {
        QuestOutcome(key: "k", day: day(back), succeeded: succeeded, deadlineMinute: deadline, count: count, targetMl: target)
    }

    /// «Два вгору — один униз»: на крок важче лише після двох успіхів поспіль на тій самій планці.
    func testDeadlineStartsFromPersonalBaseAndSteps() {
        // Ідеал кривої 13:00, людина зазвичай добирає о 14:20 — старт 14:30.
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 860, latest: 1260, history: []), 870)
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 860, latest: 1260, history: [outcome(1, true, deadline: 870)]),
                       870, "один успіх — планка тримається")
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 860, latest: 1260,
                                                history: [outcome(1, true, deadline: 870), outcome(3, true, deadline: 870)]),
                       840, "двічі поспіль — на крок раніше")
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 860, latest: 1260,
                                                history: [outcome(1, true, deadline: 840), outcome(3, true, deadline: 870)]),
                       840, "успіх на новій планці — ще тримаємо")
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 860, latest: 1260, history: [outcome(1, false, deadline: 870)]),
                       900, "ні — на крок пізніше")
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 860, latest: 1260,
                                                history: [outcome(1, true, deadline: 780), outcome(2, true, deadline: 780)]),
                       780, "раніше за ідеал не вимагаємо")
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 700, latest: 1260, history: []), 780, "хто випереджає криву — ідеал")
        XCTAssertEqual(QuestAdaptation.deadline(aim: 780, base: 1300, latest: 1260, history: []), 1260, "не пізніше години до відбою")
    }

    func testCountStartsFromUsualPlusOne() {
        XCTAssertEqual(QuestAdaptation.count(base: 2, fallback: 5, range: 3...8, history: []), 3)
        XCTAssertEqual(QuestAdaptation.count(base: nil, fallback: 5, range: 3...8, history: []), 5)
        XCTAssertEqual(QuestAdaptation.count(base: 2, fallback: 5, range: 3...8,
                                             history: [outcome(2, true, count: 4), outcome(4, true, count: 4)]), 5)
        XCTAssertEqual(QuestAdaptation.count(base: 2, fallback: 5, range: 3...8, history: [outcome(2, true, count: 4)]), 4)
        XCTAssertEqual(QuestAdaptation.count(base: 2, fallback: 5, range: 3...8, history: [outcome(2, false, count: 3)]), 3,
                       "не нижче за межу")
    }

    func testPauseAfterRepeatedFailures() {
        let fails = (1...3).map { QuestOutcome(key: "k", day: day($0), succeeded: false) }
        XCTAssertTrue(QuestAdaptation.isPaused("k", outcomes: Array(fails.prefix(2)), today: today, adaptive: false))
        XCTAssertFalse(QuestAdaptation.isPaused("k", outcomes: Array(fails.prefix(2)), today: today, adaptive: true),
                       "адаптивне спершу полегшає")
        XCTAssertTrue(QuestAdaptation.isPaused("k", outcomes: fails, today: today, adaptive: true))
        let recovered = [QuestOutcome(key: "k", day: day(1), succeeded: true)] + fails.map {
            QuestOutcome(key: "k", day: DayKey(ordinal: $0.day.ordinal - 1), succeeded: false)
        }
        XCTAssertFalse(QuestAdaptation.isPaused("k", outcomes: recovered, today: today, adaptive: true))
        let old = (15...17).map { QuestOutcome(key: "k", day: day($0), succeeded: false) }
        XCTAssertFalse(QuestAdaptation.isPaused("k", outcomes: old, today: today, adaptive: true), "через 14 днів пауза минає")
    }

    func testPersonalBlockTarget() throws {
        let block = try XCTUnwrap(DaySchedule(wakeMinutes: 480, sleepMinutes: 1320).curve(goalMl: 2000).goalBlocks()
            .first { $0.fromMinute == 720 })
        XCTAssertEqual(block.targetMl, 826)
        // Зазвичай 30 % — 248 мл; ціль — звичне + склянка, угору до 50.
        XCTAssertEqual(QuestAdaptation.blockTarget(median: 0.3, block: block, glassMl: 250, history: []), 500)
        let twice = [outcome(1, true, target: 500), outcome(2, true, target: 500)]
        XCTAssertEqual(QuestAdaptation.blockTarget(median: 0.3, block: block, glassMl: 250, history: twice), 650)
        XCTAssertEqual(QuestAdaptation.blockTarget(median: 0.3, block: block, glassMl: 250, history: [outcome(1, false, target: 500)]),
                       400, "не вдалось — на пів склянки нижче")
        XCTAssertEqual(QuestAdaptation.blockTarget(median: 0.65, block: block, glassMl: 250, history: []), 700,
                       "65 % — звичне 537 + пів склянки, угору до 50")
        XCTAssertNil(QuestAdaptation.blockTarget(median: 0.7, block: block, glassMl: 250, history: []),
                     "78 + пів склянки вже за межею зарахування — повна ціль")
        XCTAssertNil(QuestAdaptation.blockTarget(median: 0.9, block: block, glassMl: 250, history: []), "від 90 % — повна ціль")
        XCTAssertNil(QuestAdaptation.blockTarget(median: 0.55, block: block, glassMl: 250,
                                                 history: [outcome(1, true, target: 700), outcome(2, true, target: 700)]),
                     "особиста ціль доросла до межі зарахування — далі повна")
    }

    // MARK: - Пікер

    private let schedule = DaySchedule(wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    private func input(baseline: QuestBaseline = .none, outcomes: [QuestOutcome] = [], goalMedian: Int? = nil,
                       weakBlock: WeakBlock? = WeakBlock(index: 1, median: 0.6), goalDays7: Int = 7) -> DailyPickInput {
        DailyPickInput(day: today, dayNumber: 30, seed: "1700000000000", level: 6, dayRhythm: true,
                       remindersActive: true, schedule: schedule, goalMl: 2000, glassMl: 250, issueMinute: 8 * 60 + 15,
                       goalDays7: goalDays7, goalMedianMinute: goalMedian, weakBlock: weakBlock, baseline: baseline,
                       outcomes: outcomes)
    }

    private func resolve(_ key: String, _ input: DailyPickInput) throws -> QuestPick {
        DailyQuestPicker.resolve(try XCTUnwrap(QuestCatalog.definition(key)), input)
    }

    /// «5 склянок» у того, хто п'є 2–3 рази на день, не вдавалось жодного разу (аудит: 0 з 17). Тепер — звичне + 1.
    func testGlassesFollowUsualCount() throws {
        XCTAssertEqual(try resolve("daily.glasses", input(baseline: QuestBaseline(glasses: 2))).count, 3)
        XCTAssertEqual(try resolve("daily.glasses", input(baseline: QuestBaseline(glasses: 7))).count, 8,
                       "до потрібного для норми: 2000 / 250")
        XCTAssertEqual(try resolve("daily.glasses", input(baseline: QuestBaseline(glasses: 7))).difficulty, .hard)
        XCTAssertEqual(try resolve("daily.glasses", input()).count, 5, "без історії — як раніше")
    }

    /// «Норма до T» стартує зі звичного часу людини, а не на 30 хв раніше (аудит: 0 з 12 у того, хто закриває норму щодня).
    func testGoalByStartsFromUsualTime() throws {
        let baseline = QuestBaseline(shareMinutes: [100: 19 * 60 + 20])
        let pick = try resolve("daily.goalBy", input(baseline: baseline, goalMedian: 19 * 60 + 20))
        XCTAssertEqual(pick.deadlineMinute, 19 * 60 + 30)
        let after = (1...2).map { QuestOutcome(key: "daily.goalBy", day: day($0 * 2), succeeded: true, deadlineMinute: 19 * 60 + 30) }
        XCTAssertEqual(try resolve("daily.goalBy", input(baseline: baseline, outcomes: after, goalMedian: 19 * 60 + 20))
            .deadlineMinute, 19 * 60, "виконано двічі — наступного разу на 30 хв раніше")
    }

    /// Сова: половину норми зазвичай має о 16:40 — «Половина до 17:00», а не до 14:00 за кривою.
    func testHalfByFollowsLateRhythm() throws {
        let pick = try resolve("daily.halfBy", input(baseline: QuestBaseline(shareMinutes: [50: 16 * 60 + 40])))
        XCTAssertEqual(pick.deadlineMinute, 17 * 60)
    }

    /// Хто п'є склянками по 200 мл, «Склянку після підйому» в 250 мл не виконав би ніколи.
    func testWakeGlassFollowsUsualPortion() throws {
        XCTAssertEqual(try resolve("daily.wakeGlass", input(baseline: QuestBaseline(portionMl: 200))).targetMl, 200)
        XCTAssertNil(try resolve("daily.wakeGlass", input(baseline: QuestBaseline(portionMl: 400))).targetMl)
        XCTAssertEqual(QuestAdaptation.wakeGlassTarget(portionMl: 120, glassMl: 250), 150, "не менше за поріг склянки")
    }

    func testWeakBlockGetsPersonalTarget() throws {
        let pick = try resolve("daily.closeBlock", input(weakBlock: WeakBlock(index: 1, median: 0.3)))
        XCTAssertEqual(pick.blockIndex, 1)
        XCTAssertEqual(pick.targetMl, 500)
        XCTAssertNil(try resolve("daily.closeBlock", input(weakBlock: WeakBlock(index: 1, median: 0.8))).targetMl)
    }

    func testGatesAndPauses() {
        let keys = { (input: DailyPickInput) in
            Set(QuestCatalog.definitions(.rhythm).compactMap { DailyQuestPicker.candidate($0, input)?.pick.key }
                + QuestCatalog.definitions(.tempo).compactMap { DailyQuestPicker.candidate($0, input)?.pick.key })
        }
        XCTAssertFalse(keys(input(baseline: QuestBaseline(allBlocksDays14: 1, goalAheadDays7: 2))).contains("daily.allBlocks"),
                       "«Три частини» — лише тому, хто вже закривав усі три")
        XCTAssertTrue(keys(input(baseline: QuestBaseline(allBlocksDays14: 3, goalAheadDays7: 2))).contains("daily.allBlocks"))
        XCTAssertTrue(keys(input(baseline: QuestBaseline(allBlocksDays14: 3, goalAheadDays7: 2))).contains("daily.goalNoReminders"))
        XCTAssertFalse(keys(input(baseline: QuestBaseline(allBlocksDays14: 3, goalAheadDays7: 6))).contains("daily.goalNoReminders"),
                       "норма без нагадувань щодня — не виклик")
        XCTAssertFalse(keys(input(baseline: QuestBaseline(allBlocksDays14: 3, goalAheadDays7: 0))).contains("daily.goalNoReminders"),
                       "жодного разу — недосяжне")
        let failed = (2...3).map { QuestOutcome(key: "daily.everyBlock", day: day($0), succeeded: false) }
        XCTAssertFalse(keys(input(outcomes: failed)).contains("daily.everyBlock"), "двічі не вдалось — пауза")
    }
}
