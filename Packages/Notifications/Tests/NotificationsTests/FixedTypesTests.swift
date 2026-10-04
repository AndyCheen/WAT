import XCTest
import Core
import Persistence
@testable import Notifications

/// Ранкова склянка, вечірній підсумок, порятунок серії — §7, §8, §12.1.
final class FixedTypesTests: XCTestCase {
    private func plan(_ context: NotificationContext, _ preferences: NotificationPreferences = .default) -> NotificationPlan {
        NotificationPlanner.plan(context: context, preferences: preferences)
    }

    private func items(_ plan: NotificationPlan, _ type: NotificationType, day: Int = 1) -> [PlannedNotification] {
        plan.items.filter { $0.type == type && $0.dayKey.day == day }
    }

    // MARK: - Ранкова склянка (§7)

    func testMorningGlassAtWakeWhenNoIntakes() {
        let morning = items(plan(Fixture.context(at: Fixture.date(7))), .morning)
        XCTAssertEqual(morning.map { Fixture.clock($0.fireAt) }, ["08:00"])
        XCTAssertEqual(morning.first?.category, .glass, "дія «+склянка»")
        XCTAssertEqual(morning.first?.tapRoute, .customAmount(ml: 250), "етап A — тап веде в «Інше» з P")
        XCTAssertTrue(morning.first?.isFloating == true, "о 08:00 місцевого і після перельоту")
    }

    func testNoMorningGlassAfterFirstIntake() {
        let at = Fixture.date(7, 30)
        XCTAssertTrue(items(plan(Fixture.context(at: at, countedMl: 250, intakes: [at])), .morning).isEmpty)
    }

    func testCustomMorningTime() {
        var preferences = NotificationPreferences.default
        preferences.morningMinutes = 9 * 60 + 30
        XCTAssertEqual(items(plan(Fixture.context(at: Fixture.date(7)), preferences), .morning).map { Fixture.clock($0.fireAt) }, ["09:30"])
    }

    /// Вихідні: окремий розклад, якщо він увімкнений. 3 жовтня 2026 — субота.
    func testWeekendScheduleMovesMorning() {
        var preferences = NotificationPreferences.default
        preferences.weekend = DaySchedule(wakeMinutes: 9 * 60, sleepMinutes: 23 * 60)
        let saturday = items(plan(Fixture.context(at: Fixture.date(7)), preferences), .morning, day: 3)
        XCTAssertEqual(saturday.map { Fixture.clock($0.fireAt) }, ["09:00"])
    }

    /// Ранкова склянка йде за місцевим часом після зміни поясу (критерій §19.12).
    func testMorningFollowsLocalTimeAfterTimeZoneChange() {
        let lisbon = TimeZone(identifier: "Europe/Lisbon")!
        var context = Fixture.context(at: Fixture.date(day: 2, 6, zone: lisbon))
        context.timeZone = lisbon
        let morning = plan(context).items.first { $0.type == .morning && $0.dayKey.day == 2 }!
        XCTAssertEqual(Fixture.clock(morning.fireAt, zone: lisbon), "08:00")
    }

    // MARK: - Вечірній підсумок (§8, критерій §19.10)

    private func evening(countedMl: Int, intakes: [Date]? = nil, streak: StreakInput = StreakInput(),
                         freezes: Int = 0, _ preferences: NotificationPreferences = .default) -> PlannedNotification? {
        let times = intakes ?? (countedMl > 0 ? [Fixture.date(15)] : [])
        var context = Fixture.context(at: Fixture.date(16), countedMl: countedMl, intakes: times)
        context.streak = streak
        context.readyFreezes = freezes
        return plan(context, preferences).items.first { ($0.type == .evening || $0.type == .rescue) && $0.dayKey.day == 1 }
    }

    func testSituation1ClosedGoalSendsNothing() {
        XCTAssertNil(evening(countedMl: 2000))
    }

    func testSituation2ClosableIsEncouraging() {
        let item = evening(countedMl: 1700)
        XCTAssertEqual(item?.slot, "closable")
        XCTAssertEqual(item.map { Fixture.clock($0.fireAt) }, "20:00")
        XCTAssertEqual(item?.category, .glass, "дія «+склянка» лише в ситуації 2")
        XCTAssertTrue(item?.body.contains("300 мл") == true, item?.body ?? "")
    }

    func testSituation2MentionsStreakWhenYesterdayCounted() {
        let item = evening(countedMl: 1600, streak: StreakInput(countedYesterday: true, lengthEndingYesterday: 12))
        XCTAssertEqual(item?.slot, "closableStreak")
        XCTAssertTrue(item?.body.contains("12 днів") == true, item?.body ?? "")
    }

    /// Поріг «можна закрити» — min(2·P, 600): при пляшках по 0,5 л бракує й 600 мл.
    func testClosableThresholdFollowsTypicalPortion() {
        XCTAssertEqual(evening(countedMl: 1450)?.slot, "soothing", "550 > 2 × 250")
        var context = Fixture.context(at: Fixture.date(16), countedMl: 1450, intakes: [Fixture.date(15)])
        context.portionHistoryMl = [500, 500, 500]
        XCTAssertEqual(plan(context).items.first { $0.type == .evening }?.slot, "closable", "550 ≤ min(1000, 600)")
    }

    func testSituation3RescuesStreak() {
        let streak = StreakInput(countedYesterday: true, lengthEndingYesterday: 12)
        let item = evening(countedMl: 500, streak: streak, freezes: 1)
        XCTAssertEqual(item?.type, .rescue)
        XCTAssertEqual(item?.slot, "pm")
        XCTAssertNil(item?.category, "кнопки «Заморозити» в сповіщенні немає")
        XCTAssertEqual(item?.tapRoute, .freezeCard)
        XCTAssertEqual(item?.title, "🧊 Серію 12 днів ще збережеш")
    }

    func testSituation4SoothingNeverMentionsStreak() {
        let item = evening(countedMl: 800, streak: StreakInput(countedYesterday: true, lengthEndingYesterday: 12))
        XCTAssertEqual(item?.slot, "soothing", "без заморозки порятунку немає")
        XCTAssertFalse(item!.title.lowercased().contains("сері") || item!.body.lowercased().contains("сері"))
        XCTAssertNil(item?.category)
    }

    func testSituation5NoIntakesSendsNothing() {
        XCTAssertNil(evening(countedMl: 0, intakes: []))
    }

    // MARK: - Порятунок серії (§12.1, критерій §19.11)

    func testMorningRescueMergesWithMorningGlass() {
        var context = Fixture.context(at: Fixture.date(7))
        context.streak = StreakInput(countedYesterday: false, countedDayBefore: true, lengthEndingDayBefore: 9)
        context.readyFreezes = 1
        let today = plan(context).items.filter { $0.dayKey.day == 1 && Fixture.clock($0.fireAt) == "08:00" }
        XCTAssertEqual(today.map(\.type), [.rescue], "одне сповіщення замість двох")
        XCTAssertEqual(today.first?.category, .glass, "бере дію ранкової склянки")
        XCTAssertEqual(today.first?.tapRoute, .freezeCard)
        XCTAssertEqual(today.first?.title, "🧊 Серію 9 днів ще врятуєш")
    }

    func testShortStreakIsNotRescued() {
        XCTAssertEqual(evening(countedMl: 500, streak: StreakInput(countedYesterday: true, lengthEndingYesterday: 2), freezes: 1)?.type,
                       .evening)
    }

    func testNoFreezeNoRescue() {
        XCTAssertEqual(evening(countedMl: 500, streak: StreakInput(countedYesterday: true, lengthEndingYesterday: 5))?.type,
                       .evening)
    }

    /// Не більше двох на серію: увечері, коли норму вже не наздогнати, і наступного ранку.
    func testAtMostTwoRescuesPerStreak() {
        var context = Fixture.context(at: Fixture.date(21), countedMl: 2000, intakes: [Fixture.date(12)])
        context.streak = StreakInput(countedToday: true, countedYesterday: true, lengthEndingToday: 6, lengthEndingYesterday: 5)
        context.readyFreezes = 2
        let rescues = plan(context).items.filter { $0.type == .rescue }
        XCTAssertEqual(rescues.map(\.id), ["wt.rescue.2026-10-02.pm", "wt.rescue.2026-10-03.am"])
    }

    /// «Не сьогодні» гасить нагадування й вечірній підсумок до 00:00, але не порятунок (критерій §19.8).
    func testPauseSilencesMotivationalTypesButNotRescue() {
        var preferences = NotificationPreferences.default
        preferences.pausedUntil = Fixture.date(day: 2, 0)
        var context = Fixture.context(at: Fixture.date(15), countedMl: 500, intakes: [Fixture.date(14)])
        context.streak = StreakInput(countedYesterday: true, lengthEndingYesterday: 5)
        context.readyFreezes = 1
        let today = plan(context, preferences).items.filter { $0.dayKey.day == 1 }
        XCTAssertEqual(today.map(\.type), [.rescue])

        context.readyFreezes = 0
        XCTAssertTrue(plan(context, preferences).items.filter { $0.dayKey.day == 1 }.isEmpty)
        XCTAssertFalse(plan(context, preferences).items.filter { $0.dayKey.day == 2 }.isEmpty, "завтра пауза знята")
    }

    func testMasterSwitchOffPlansNothing() {
        var preferences = NotificationPreferences.default
        preferences.isEnabled = false
        XCTAssertTrue(plan(Fixture.context(at: Fixture.date(7)), preferences).items.isEmpty)
    }
}
