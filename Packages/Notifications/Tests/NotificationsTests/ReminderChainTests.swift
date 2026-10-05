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
        // E(10:00) = 321 > A → R = 321, ціль 571 → 11:21:41 → 11:22 (у межах [11:00, 13:00]).
        XCTAssertEqual(reminders(plan(context)), ["11:22", "11:52", "13:52", "14:22"])
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
        XCTAssertEqual(reminders(plan(context, preferences)).first, "09:17", "k = 0,75")
        preferences.cadence = .pace(.rarer)
        XCTAssertEqual(reminders(plan(context, preferences)).first, "10:18", "k = 1,5")
    }

    func testEqualIntervals() {
        var preferences = NotificationPreferences.default
        preferences.cadence = .interval(minutes: 90)
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)), ["09:30", "10:00", "12:00", "12:30"])
    }

    func testFollowUpCanBeTurnedOff() {
        var preferences = NotificationPreferences.default
        preferences.followUpEnabled = false
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)), ["09:37", "12:07"])
    }

    /// Після S − 2 год працює вечірній підсумок; без нього відсічка — S − 1 год.
    ///
    /// Порція о 18:15, а не о 18:30, як у «забудька»: зі спадом перед сном (WAT-43) після 18:30
    /// темп уже не встигає до 21:00, і різниці між відсічками не було б видно.
    func testCutoffDependsOnEveningSummary() {
        let intakeTimes = [Fixture.date(8, 30), Fixture.date(13), Fixture.date(15), Fixture.date(18, 15)]
        let context = Fixture.context(at: Fixture.date(18, 15), countedMl: 1050, intakes: intakeTimes)
        XCTAssertEqual(reminders(plan(context)), [], "20:38 — уже після 20:00")

        var preferences = NotificationPreferences.default
        preferences.eveningEnabled = false
        // R = E(18:15) = 1667, ціль 1917; E(20:00) = 1879, далі половинний темп → 20:37:30 → 20:38.
        XCTAssertEqual(reminders(plan(context, preferences)), ["20:38"], "повторне 21:08 — після 21:00")
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
        XCTAssertEqual(ids.first, "wt.reminder.2026-10-01.0937")
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
        XCTAssertEqual(reminders(plan(Fixture.context(at: Fixture.date(7)), preferences)).first, "09:37")
    }
}
