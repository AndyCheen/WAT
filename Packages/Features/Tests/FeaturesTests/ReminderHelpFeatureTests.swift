import XCTest
import SwiftData
import Core
import Persistence
import Notifications
@testable import Features

/// «Нагадувань забагато?» (WAT-67, SPEC-NOTIFICATIONS §32): разове вікно на чистому відкритті головного, коли
/// нагадування за тиждень майже не допомагали; відповідь змінює налаштування сповіщень.
@MainActor
final class ReminderHelpFeatureTests: XCTestCase {
    private var services: AppServices!
    private var container: ModelContainer!

    private static func date(month: Int = 10, day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = month; parts.day = day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: parts)!
    }

    /// Тиждень по два нагадування на день, жодне без справжньої відповіді. Журнал — до `bootstrap()`: сховище
    /// журналу сервісу кешує записи при першому читанні.
    private func makeServices(ignoredWeek: Bool) {
        container = Database.makeInMemoryContainer()
        if ignoredWeek {
            let store = NotificationStore(context: container.mainContext)
            for day in 24...30 {
                for hour in [11, 15] {
                    let fireAt = Self.date(month: 9, day: day, hour)
                    store.insert(NotificationLog(identifier: "wt.reminder.2026-09-\(day).\(hour)00", type: .reminder,
                                                 slot: "primary", dayKey: "2026-09-\(day)", fireAt: fireAt,
                                                 plannedAt: fireAt, variant: 0))
                }
            }
            store.save()
        }
        services = AppServices(container: container, clock: FixedClock(now: Self.date(day: 1, 10)),
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
        services.profile.notificationsEnabled = true
    }

    func testOfferedOnceWhenRemindersDidNotHelp() async {
        makeServices(ignoredWeek: true)
        await services.notifications.refreshAuthorization()
        let model = HomeViewModel(services: services)
        XCTAssertTrue(services.shouldOfferReminderHelp)

        model.offerScheduleIfNeeded(activation: 1, isHomeOnTop: true)
        XCTAssertEqual(model.sheet, .reminderHelp)
        model.answerReminderHelp(.rarer)
        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.toast?.message, "Нагадування — рідше й без повторних")
        XCTAssertEqual(services.notifications.settings.reminderFrequency, .rarer)
        XCTAssertFalse(services.notifications.settings.followUpEnabled)
        XCTAssertFalse(services.shouldOfferReminderHelp, "питання разове")
    }

    func testCheckpointsOnlyAndKeepChoices() async {
        makeServices(ignoredWeek: true)
        await services.notifications.refreshAuthorization()
        services.answerReminderHelp(.checkpointsOnly)
        XCTAssertFalse(services.notifications.settings.remindersEnabled)
        XCTAssertTrue(services.notifications.settings.checkpointsEnabled, "чекпоінти лишаються")

        services.answerReminderHelp(.keep)
        XCTAssertFalse(services.notifications.preferences().adaptiveReminders, "«Лишити як є» — і самі не рідшають")
    }

    func testNotOfferedWhileRemindersHelpOrWithoutHistory() async {
        makeServices(ignoredWeek: false)
        await services.notifications.refreshAuthorization()
        XCTAssertFalse(services.shouldOfferReminderHelp, "без історії судити нема з чого")
        let model = HomeViewModel(services: services)
        model.offerScheduleIfNeeded(activation: 1, isHomeOnTop: true)
        XCTAssertNil(model.sheet)
    }
}
