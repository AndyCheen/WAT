import XCTest
import Core
import Persistence
@testable import Notifications

/// Чекпоінти частин доби — SPEC-NOTIFICATIONS §9. При 08:00–22:00 і нормі 2000 мл чекпоінти
/// о 11:15 (до 12:00, ціль 649 мл) і 16:15 (до 17:00, 780 мл); у вечора чекпоінта немає.
final class CheckpointTests: XCTestCase {
    private func checkpoints(_ context: NotificationContext,
                             _ preferences: NotificationPreferences = .default) -> [PlannedNotification] {
        NotificationPlanner.plan(context: context, preferences: preferences).items
            .filter { $0.type == .checkpoint && $0.dayKey.day == 1 }
    }

    /// Одна склянка о 08:30: до 12:00 бракує 399 мл (≤ 2·P), відставання всередині частини — 270 мл.
    private var oneMorningGlass: NotificationContext {
        Fixture.context(at: Fixture.date(9), portions: [Portion(at: Fixture.date(8, 30), ml: 250)])
    }

    // MARK: - День «забудька» з усіма типами (§6.3)

    /// Дослівно таблиця §6.3: чекпоінт 11:15 займає місце нагадування 11:09, повторне — від нього;
    /// о 16:15 чекпоінта немає (відставання в частині 112 мл < ½ порції).
    func testForgetfulDayWithAllTypes() {
        let day = intakes([(8, 30, 250), (13, 0, 250), (15, 0, 300), (18, 30, 250)])
        XCTAssertEqual(DaySimulator().timeline(intakes: day), [
            "08:00 morning", "11:15 checkpoint", "11:45 reminder", "14:37 reminder",
            "16:37 reminder", "17:07 reminder", "20:00 evening"
        ])
    }

    func testCheckpointTextNamesDeadlineAndAmount() {
        let checkpoint = checkpoints(oneMorningGlass).first
        XCTAssertEqual(checkpoint?.id, "wt.checkpoint.2026-10-01.noon")
        XCTAssertEqual(checkpoint.map { Fixture.clock($0.fireAt) }, "11:15")
        XCTAssertEqual(checkpoint?.category, .reminder, "ті самі дії, що в нагадування (§16.4)")
        XCTAssertEqual(checkpoint?.tapRoute, .customAmount(ml: 250))
        let text = (checkpoint?.title ?? "") + " " + (checkpoint?.body ?? "")
        XCTAssertTrue(text.contains("400 мл"), "бракує 399 — округлено вгору до 50: \(text)")
        XCTAssertTrue(text.contains("12:00"), text)
    }

    // MARK: - Умови §9

    /// «На темпі» з §6.1 (склянка кожні 1 год 45 хв): ранкову частину закриває сам, а в «дні»
    /// (12–17) природний інтервал — 97 хв, тож до 16:15 відстає на 162 мл ≥ ½P. Рівно те, що
    /// обіцяють §6.3 і §13.1: «ранкова склянка, можливо, один чекпоінт і вечірнє «ще 250 мл»»
    /// — і жодного нагадування.
    func testOnPaceUserGetsAtMostOneCheckpoint() {
        let day = (0..<8).map { step -> (Int, Int, Int) in
            let minutes = 8 * 60 + step * 105
            return (minutes / 60, minutes % 60, 250)
        }
        XCTAssertEqual(DaySimulator().timeline(intakes: intakes(day)), ["08:00 morning", "16:15 checkpoint", "20:00 evening"])
    }

    /// Відставання всередині частини менше за ½ порції — чекпоінта немає, навіть коли до цілі
    /// лишається трохи (умова 1): о 11:15 за темпом 520 мл, випито 500.
    func testSmallLagInsidePartIsNotACheckpoint() {
        let portions = [Portion(at: Fixture.date(8), ml: 250), Portion(at: Fixture.date(9, 45), ml: 250)]
        XCTAssertTrue(checkpoints(Fixture.context(at: Fixture.date(10), portions: portions)).isEmpty)
    }

    /// Бракує більше ніж 2·P — недосяжний чекпоінт не мотивує (умова 2).
    func testUnreachableCheckpointIsSkipped() {
        XCTAssertTrue(checkpoints(Fixture.context(at: Fixture.date(9))).isEmpty, "бракує всі 649 мл")
    }

    /// Склянка о 06:30 при підйомі о 08:00 зараховується ранку (WAT-39): разом із порціями до
    /// 12:00 ціль закрита — чекпоінта немає.
    func testPortionBeforeWakeClosesMorningCheckpoint() {
        let portions = [Portion(at: Fixture.date(6, 30), ml: 250), Portion(at: Fixture.date(8, 30), ml: 250),
                        Portion(at: Fixture.date(10), ml: 200)]
        XCTAssertTrue(checkpoints(Fixture.context(at: Fixture.date(10, 5), portions: portions)).filter { $0.slot == "noon" }.isEmpty)
    }

    /// Рання склянка зменшує й відставання: 06:30 + 08:30 — це 500 мл ранку, о 11:15 за темпом
    /// 519, відставання 19 < ½P. Без неї був би той самий чекпоінт, що й в `oneMorningGlass`.
    func testPortionBeforeWakeCountsTowardLag() {
        let portions = [Portion(at: Fixture.date(6, 30), ml: 250), Portion(at: Fixture.date(8, 30), ml: 250)]
        XCTAssertTrue(checkpoints(Fixture.context(at: Fixture.date(9), portions: portions)).filter { $0.slot == "noon" }.isEmpty)
        XCTAssertFalse(checkpoints(oneMorningGlass).filter { $0.slot == "noon" }.isEmpty)
    }

    func testNoCheckpointOnceDayGoalIsMet() {
        let portions = [Portion(at: Fixture.date(8, 30), ml: 250), Portion(at: Fixture.date(8, 40), ml: 1800)]
        XCTAssertTrue(checkpoints(Fixture.context(at: Fixture.date(9), portions: portions)).isEmpty)
    }

    func testPauseAndToggleSilenceCheckpoints() {
        var paused = NotificationPreferences.default
        paused.pausedUntil = Fixture.date(day: 2, 0)
        XCTAssertTrue(checkpoints(oneMorningGlass, paused).isEmpty, "«Не сьогодні» гасить і чекпоінти (§6.4)")

        var off = NotificationPreferences.default
        off.checkpointsEnabled = false
        XCTAssertTrue(checkpoints(oneMorningGlass, off).isEmpty)
    }

    /// Режим «просто норма» (WAT-42) гасить чекпоінти, хоч їхній власний перемикач увімкнений; решта
    /// дня — та сама: нагадування стоять там, де стояли б без чекпоінта.
    func testDayRhythmOffSilencesCheckpointsButKeepsReminders() {
        var plain = NotificationPreferences.default
        plain.dayRhythmEnabled = false
        XCTAssertTrue(plain.checkpointsEnabled)
        XCTAssertTrue(checkpoints(oneMorningGlass, plain).isEmpty)

        var noCheckpoints = NotificationPreferences.default
        noCheckpoints.checkpointsEnabled = false
        let today: (NotificationPreferences) -> [String] = { preferences in
            NotificationPlanner.plan(context: self.oneMorningGlass, preferences: preferences).items
                .filter { $0.dayKey.day == 1 }.map { "\(Fixture.clock($0.fireAt)) \($0.type)" }
        }
        XCTAssertEqual(today(plain), today(noCheckpoints))
        XCTAssertFalse(today(plain).isEmpty)
    }

    /// Тихий період зсуває чекпоінт на свій кінець, поки той ще до дедлайну.
    func testQuietPeriodShiftsCheckpoint() {
        var preferences = NotificationPreferences.default
        preferences.quietWindows = [QuietWindow(fromMinutes: 11 * 60, toMinutes: 11 * 60 + 30)]
        XCTAssertEqual(checkpoints(oneMorningGlass, preferences).map { Fixture.clock($0.fireAt) }, ["11:30"])

        preferences.quietWindows = [QuietWindow(fromMinutes: 11 * 60, toMinutes: 12 * 60 + 30)]
        XCTAssertTrue(checkpoints(oneMorningGlass, preferences).isEmpty, "після 12:00 чекпоінт втрачає сенс")
    }

    /// Буст до кінця дня — у тексті подвійний XP.
    func testBoostDoublesXpInText() {
        var context = oneMorningGlass
        context.boostExpiresAt = Fixture.date(day: 2, 0)
        let checkpoint = checkpoints(context).first!
        if checkpoint.body.contains("XP") {
            XCTAssertTrue(checkpoint.body.contains("20 XP"), checkpoint.body)
        }
    }

    // MARK: - Злиття з нагадуванням

    /// Основне нагадування, що падає у вікно чекпоінта, окремо не надсилається.
    func testPrimaryReminderInWindowMergesIntoCheckpoint() {
        let plan = NotificationPlanner.plan(context: oneMorningGlass, preferences: .default)
        let today = plan.items.filter { $0.dayKey.day == 1 && $0.type != .evening }
        XCTAssertEqual(today.map { "\(Fixture.clock($0.fireAt)) \($0.slot)" },
                       ["11:15 noon", "11:45 followUp", "13:45 primary", "14:15 followUp"])
    }
}
