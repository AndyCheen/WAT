import XCTest
import Core
import Persistence
@testable import Notifications

/// Ланцюг нагадувань — §6.2 поза чотирма днями з ТЗ.
final class ReminderChainTests: XCTestCase {
    private func reminders(_ plan: NotificationPlan, day: Int = 1) -> [String] {
        plan.items.filter { $0.type == .reminder && $0.dayKey.day == day }.map { Fixture.clock($0.fireAt) }
    }

    private func plan(_ context: NotificationContext, _ preferences: NotificationPreferences = .default,
                      journal: NotificationJournal = .empty) -> NotificationPlan {
        NotificationPlanner.plan(context: context, preferences: preferences, journal: journal)
    }

    /// Порція перебудовує ланцюг від себе.
    func testIntakeRestartsChain() {
        let at = Fixture.date(10)
        let context = Fixture.context(at: at, countedMl: 250, intakes: [at])
        // E(10:00) = 303 > A → R = 303, ціль 553 → 11:26:42 → 11:27 (у межах [11:00, 13:00]).
        XCTAssertEqual(reminders(plan(context)), ["11:27", "11:57", "13:57", "14:27"])
    }

    /// Відкриття застосунку без порції: якір той самий, але перше нагадування — не раніше ніж
    /// через 30 хв, і рахунок проігнорованих блоків починається заново (§6.2, «Скидання»).
    func testAppOpenPushesChainAtLeastThirtyMinutes() {
        let intake = Fixture.date(8, 30)
        var context = Fixture.context(at: Fixture.date(12), countedMl: 250, intakes: [intake])
        context.lastInteractionAt = Fixture.date(12)
        XCTAssertEqual(reminders(plan(context)), ["12:30", "13:00", "15:00", "15:30"])
    }

    /// «Нагадати за годину» — одне основне через 60 хв, далі ланцюг як звичайно.
    func testSnoozeGivesOnePrimaryAfterAnHour() {
        let intake = Fixture.date(8, 30)
        let context = Fixture.context(at: Fixture.date(11, 10), countedMl: 250, intakes: [intake])
        let journal = NotificationJournal(entries: [
            JournalEntry(identifier: "wt.reminder.2026-10-01.1109", type: .reminder, slot: "primary",
                         dayKey: DayKey(rawValue: "2026-10-01"), fireAt: Fixture.date(11, 9),
                         response: .snooze, respondedAt: Fixture.date(11, 10))
        ])
        let result = plan(context, journal: journal)
        XCTAssertEqual(reminders(result).first, "12:10")
        XCTAssertEqual(result.items.first { $0.type == .reminder }?.slot, "primary")
    }

    func testFrequencies() {
        let context = Fixture.context(at: Fixture.date(7))
        var preferences = NotificationPreferences.default
        preferences.cadence = .pace(.more)
        XCTAssertEqual(reminders(plan(context, preferences)).first, "09:20", "k = 0,75")
        preferences.cadence = .pace(.rarer)
        XCTAssertEqual(reminders(plan(context, preferences)).first, "10:25", "k = 1,5")
    }

    func testEqualIntervals() {
        var preferences = NotificationPreferences.default
        preferences.cadence = .interval(minutes: 90)
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)), ["09:30", "10:00", "12:00", "12:30"])
    }

    func testFollowUpCanBeTurnedOff() {
        var preferences = NotificationPreferences.default
        preferences.followUpEnabled = false
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)), ["09:42", "12:12"])
    }

    /// Після S − 2 год працює вечірній підсумок; без нього відсічка — S − 1 год.
    func testCutoffDependsOnEveningSummary() {
        let intakeTimes = [Fixture.date(8, 30), Fixture.date(13), Fixture.date(15), Fixture.date(18, 30)]
        let context = Fixture.context(at: Fixture.date(18, 30), countedMl: 1050, intakes: intakeTimes)
        XCTAssertEqual(reminders(plan(context)), [], "20:42 — уже після 20:00")

        var preferences = NotificationPreferences.default
        preferences.eveningEnabled = false
        // R = E(18:30) = 1600, ціль 1850 → 20:41:15 → 20:42.
        XCTAssertEqual(reminders(plan(context, preferences)), ["20:42"], "повторне 21:12 — після 21:00")
    }

    func testClosedGoalSilencesReminders() {
        let at = Fixture.date(12)
        XCTAssertEqual(reminders(plan(Fixture.context(at: at, countedMl: 2000, intakes: [at]))), [])
    }

    func testRemindersCanBeTurnedOff() {
        var preferences = NotificationPreferences.default
        preferences.remindersEnabled = false
        XCTAssertTrue(plan(Fixture.context(at: Fixture.date(7)), preferences).items.allSatisfy { $0.type != .reminder })
    }

    /// Ідентифікатор нагадування — `HHmm` моменту: перебудований ланцюг не зіткнеться з
    /// доставленими рядками журналу (рішення від 04.10.2026).
    func testReminderIdentifiersUseClockTime() {
        let ids = plan(Fixture.context(at: Fixture.date(7))).items.filter { $0.type == .reminder }.map(\.id)
        XCTAssertEqual(ids.first, "wt.reminder.2026-10-01.0942")
        XCTAssertFalse(plan(Fixture.context(at: Fixture.date(7))).items.first { $0.type == .reminder }!.isFloating,
                       "нагадування — абсолютний момент від порції")
    }

    /// Тихий період, що закінчується після відсічки, скасовує нагадування.
    func testQuietPeriodPastCutoffCancels() {
        var preferences = NotificationPreferences.default
        preferences.quietWindows = [QuietWindow(fromMinutes: 9 * 60, toMinutes: 21 * 60)]
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)), [])
    }

    /// Маска днів: тихий період лише по вівторках не чіпає четвер.
    func testQuietPeriodRespectsWeekdays() {
        var preferences = NotificationPreferences.default
        preferences.quietWindows = [QuietWindow(weekdayMask: 0b0000010, fromMinutes: 9 * 60, toMinutes: 12 * 60)]
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)).first, "09:42")
    }
}
