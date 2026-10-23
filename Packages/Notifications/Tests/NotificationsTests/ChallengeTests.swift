import XCTest
import Core
import Persistence
@testable import Notifications

/// Несподіване завдання — SPEC-QUESTS §6.6: приходить у мить появи, забирає основне нагадування у вікні
/// [−45, +30], не зсувається й поступається сильнішим.
final class ChallengeTests: XCTestCase {
    private func slot(_ kind: SurpriseSlot.Kind = .glassNow, at hour: Int, _ minute: Int = 0, window: Int = 60,
                      targetMl: Int = 250, leftMl: Int = 250, blockName: String? = nil,
                      weekday: Int? = nil) -> SurpriseSlot {
        let fireAt = Fixture.date(hour, minute)
        return SurpriseSlot(kind: kind, fireAt: fireAt, deadline: fireAt.addingTimeInterval(TimeInterval(window * 60)),
                            targetMl: targetMl, leftMl: leftMl, blockName: blockName, weekdayIndex: weekday)
    }

    private func plan(_ surprise: SurpriseSlot, at now: Date = Fixture.date(9), countedMl: Int = 0,
                      intakes: [Date] = [], journal: NotificationJournal = .empty,
                      preferences: NotificationPreferences = .default) -> [PlannedNotification] {
        var context = Fixture.context(at: now, countedMl: countedMl, intakes: intakes)
        context.surprise = surprise
        return NotificationPlanner.plan(context: context, preferences: preferences, journal: journal).items
            .filter { $0.dayKey.day == 1 }
    }

    private func challenge(_ items: [PlannedNotification]) -> PlannedNotification? {
        items.first { $0.type == .challenge }
    }

    func testIdentifierRouteAndActions() {
        let item = challenge(plan(slot(at: 14, 30)))
        XCTAssertEqual(item?.id, "wt.challenge.2026-10-01.1430")
        XCTAssertEqual(item?.fireAt, Fixture.date(14, 30))
        XCTAssertEqual(item?.category, .reminder, "«+склянка», як у нагадування")
        XCTAssertEqual(item?.tapRoute, .home, "тап — на головний, до картки")
        XCTAssertEqual(item?.isFloating, false)
    }

    /// День «забудька» з чекпоінтами (CheckpointTests): несподіване о 14:45 забирає нагадування 14:31, а повторне
    /// рахується вже від нього.
    func testAbsorbsPrimaryReminderInWindow() {
        let day = intakes([(8, 30, 250), (13, 0, 250), (15, 0, 300), (18, 30, 250)])
        var simulator = DaySimulator()
        simulator.base = { now in
            var context = Fixture.context(at: now)
            context.surprise = self.slot(at: 14, 45)
            return context
        }
        let timeline = simulator.timeline(intakes: day)
        XCTAssertTrue(timeline.contains("14:45 challenge"), "\(timeline)")
        XCTAssertFalse(timeline.contains("14:31 reminder"), "несподіване замінює нагадування: \(timeline)")
    }

    func testNeverMovesAndYieldsToStronger() {
        // Ранкова склянка о 08:00 сильніша: несподіване о 08:15 не зсувається, а зникає зі сповіщень.
        XCTAssertNil(challenge(plan(slot(at: 8, 15), at: Fixture.date(7))))
        // Вечір о 20:00 — так само.
        let evening = plan(slot(at: 19, 45), at: Fixture.date(19), countedMl: 1700)
        XCTAssertNil(challenge(evening))
        XCTAssertNotNil(evening.first { $0.type == .evening })
    }

    func testClosedGoalOrPassedMomentHasNoChallenge() {
        XCTAssertNil(challenge(plan(slot(at: 14), countedMl: 2000)), "норму закрито")
        XCTAssertNil(challenge(plan(slot(at: 14), at: Fixture.date(14, 5))), "уже з'явилось — сповіщення не наздоганяє")
        var paused = NotificationPreferences.default
        paused.pausedUntil = Fixture.date(day: 2, 0)
        XCTAssertNil(challenge(plan(slot(at: 14), preferences: paused)), "«Не сьогодні»")
    }

    /// Ліміт 8 (§13.1): несподіване скорочується після нагадувань і чекпоінтів, але раніше за ранок і вечір.
    func testDailyCapOrder() {
        func shown(_ count: Int) -> NotificationJournal {
            NotificationJournal(entries: (0..<count).map { index in
                let at = Fixture.date(8, 0).addingTimeInterval(TimeInterval(index * 31 * 60))
                return JournalEntry(identifier: "wt.reminder.2026-10-01.\(index)", type: .reminder, slot: "primary",
                                    dayKey: DayKey(rawValue: "2026-10-01"), fireAt: at)
            })
        }
        // Бракує 300 мл — вечірній «можна закрити» о 20:00 (§8, ситуація 2).
        let now = Fixture.date(12, 30)
        let six = plan(slot(at: 15), at: now, countedMl: 1700, intakes: [Fixture.date(12)], journal: shown(6))
        XCTAssertNotNil(challenge(six))
        XCTAssertNotNil(six.first { $0.type == .evening })
        XCTAssertFalse(six.contains { $0.type == .reminder }, "нагадування скорочено першими")

        let seven = plan(slot(at: 15), at: now, countedMl: 1700, intakes: [Fixture.date(12)], journal: shown(7))
        XCTAssertNil(challenge(seven))
        XCTAssertNotNil(seven.first { $0.type == .evening }, "вечір сильніший")
    }

    func testTextsPerKind() {
        let glass = challenge(plan(slot(at: 14, 30)))!
        XCTAssertEqual(glass.title, "⚡ Несподіване завдання")
        XCTAssertEqual(glass.body, "Склянка до 15:30 — і приз «Подвійний XP» твій")

        let block = challenge(plan(slot(.closeBlock, at: 12, window: 300, targetMl: 826, leftMl: 280,
                                        blockName: "день")))!
        XCTAssertEqual(block.title, "⚡ Закрий день до 17:00")
        XCTAssertEqual(block.body, "Ще 300 мл — і приз «Подвійний XP» твій", "вгору до 50")

        let weekday = challenge(plan(slot(.weekday, at: 9, 30, window: 630, targetMl: 2000, leftMl: 2000, weekday: 5),
                                     at: Fixture.date(9)))!
        XCTAssertEqual(weekday.title, "⚡ Субота з нормою")
        XCTAssertTrue(weekday.body.contains("Норма до 20:00"), weekday.body)

        var ounces = NotificationPreferences.default
        ounces.volumeUnit = .usFluidOunces
        ounces.timeFormat = .hours12
        let flash = challenge(plan(slot(.flash, at: 16, 10, window: 15, targetMl: 148, leftMl: 148),
                                   preferences: ounces))!
        XCTAssertEqual(flash.title, "⚡ Блискавка: 15 хвилин")
        XCTAssertEqual(flash.body, "5 унц. до 4:25 пп — встигнеш? Нагорода — приз «Подвійний XP»")
    }
}
