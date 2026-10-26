import XCTest
import Core
import Persistence
@testable import Notifications

/// «Нагадування не допомагають» (WAT-67, §32): хто за тиждень справжньо відповів менше ніж на 30 % нагадувань,
/// отримує їх рідше й без повторних — а хто відповідає, нічого не втрачає.
final class ReminderFatigueTests: XCTestCase {
    private let today = DayKey(rawValue: "2026-10-01")

    /// Тиждень по два нагадування на день; `answered` з них — відповідь за `minutes` хвилин.
    private func week(answered: Int, after minutes: Double = 5, response: NotificationResponseKind = .intake) -> NotificationJournal {
        var entries: [JournalEntry] = []
        for day in 24...30 {
            for hour in [11, 15] {
                let fireAt = Fixture.date(day: day, hour, month: 9)
                let isAnswered = entries.count < answered
                entries.append(JournalEntry(
                    identifier: "wt.reminder.2026-09-\(day).\(hour)00", type: .reminder, slot: "primary",
                    dayKey: DayKey(rawValue: "2026-09-\(day)"), fireAt: fireAt, status: .delivered,
                    response: isAnswered ? response : .none,
                    respondedAt: isAnswered ? fireAt.addingTimeInterval(minutes * 60) : nil
                ))
            }
        }
        return NotificationJournal(entries: entries)
    }

    func testRealResponsesOnlyCount() {
        XCTAssertEqual(week(answered: 2).reminderResponseShare(before: today) ?? -1, 2.0 / 14, accuracy: 1e-9)
        XCTAssertEqual(week(answered: 6, after: 40).reminderResponseShare(before: today), 0,
                       "порція через 40 хв — збіг, а не відповідь")
        XCTAssertEqual(week(answered: 3, response: .open).reminderResponseShare(before: today) ?? -1, 3.0 / 14,
                       accuracy: 1e-9, "тап по сповіщенню — відповідь")
        XCTAssertTrue(week(answered: 4).remindersIgnored(before: today), "4 з 14 — менше за 30 %")
        XCTAssertFalse(week(answered: 5).remindersIgnored(before: today), "5 з 14 — понад 30 %")
    }

    func testTooFewDeliveredToJudge() {
        let journal = NotificationJournal(entries: Array(week(answered: 0).entries.prefix(9)))
        XCTAssertNil(journal.reminderResponseShare(before: today))
        XCTAssertFalse(journal.remindersIgnored(before: today))
    }

    private func reminders(_ journal: NotificationJournal, _ preferences: NotificationPreferences = .default) -> [String] {
        let at = Fixture.date(10)
        let context = Fixture.context(at: at, countedMl: 250, intakes: [at])
        return NotificationPlanner.plan(context: context, preferences: preferences, journal: journal).items
            .filter { $0.type == .reminder && $0.dayKey == today }
            .map { "\(Fixture.clock($0.fireAt)) \($0.slot)" }
    }

    func testIgnoredRemindersBecomeRarerWithoutFollowUps() {
        let usual = reminders(week(answered: 7))
        XCTAssertEqual(usual.filter { $0.hasSuffix("followUp") }.count, 2, "хто відповідає — звичайний ланцюг")

        let softened = reminders(week(answered: 0))
        XCTAssertTrue(softened.allSatisfy { $0.hasSuffix("primary") }, "без повторних: \(softened)")
        XCTAssertLessThan(softened.count, usual.count)
        XCTAssertGreaterThan(softened.first ?? "", usual.first ?? "", "частота «Рідше» — перше пізніше")
    }

    func testKeepChoiceDisablesSoftening() {
        var preferences = NotificationPreferences.default
        preferences.adaptiveReminders = false
        XCTAssertEqual(reminders(week(answered: 0), preferences), reminders(week(answered: 7), preferences))
    }
}
