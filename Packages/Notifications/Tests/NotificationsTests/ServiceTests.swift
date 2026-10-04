import XCTest
import SwiftData
import Core
import Persistence
import Metrics
@testable import Notifications

/// Сервіс сповіщень на in-memory базі й фейковому центрі: дифф запитів, журнал, атрибуція,
/// дозвіл (§16.2–§16.5, критерії §19.1, 2, 6, 7).
@MainActor
final class NotificationServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedClock!
    private var metrics: MetricsService!
    private var store: NotificationStore!
    private var profiles: ProfileRepository!
    private var center: InMemoryNotificationCenter!
    private var service: NotificationService!
    private var drank = 0
    private var intakes: [Date] = []

    override func setUp() async throws {
        try await super.setUp()
        container = Database.makeInMemoryContainer()
        let context = container.mainContext
        clock = FixedClock(now: Fixture.date(7))
        let calendar = CalendarService(clock: clock)
        metrics = MetricsService(store: MetricStore(context: context), calendar: calendar)
        store = NotificationStore(context: context)
        profiles = ProfileRepository(context: context)
        center = InMemoryNotificationCenter()
        service = NotificationService(store: store, profiles: profiles, metrics: metrics,
                                      calendar: calendar, center: center)
        service.bootstrap()
        service.contextProvider = { [unowned self] in
            Fixture.context(at: self.clock.now, countedMl: self.drank, intakes: self.intakes)
        }
    }

    private func intake(_ ml: Int, at date: Date, override identifier: String? = nil) {
        clock.set(date)
        drank += ml
        intakes.append(date)
        if let identifier { service.beginAttribution(identifier: identifier) }
        metrics.record(MetricEvent(name: .intakeAdded, value: Double(ml), occurredAt: date, sourceRef: UUID()))
        service.endAttribution()
        metrics.commit()
    }

    private var scheduledIds: [String] { center.scheduled.map(\.identifier) }

    func testReschedulePutsPlanIntoTheCenter() async {
        await service.rescheduleNow()
        XCTAssertTrue(scheduledIds.contains("wt.morning.2026-10-01"))
        XCTAssertTrue(scheduledIds.contains("wt.reminder.2026-10-01.0942"))
        XCTAssertEqual(center.categories.map(\.id), ["REMINDER", "GLASS"])
        XCTAssertEqual(center.categories.first?.actions.first?.title, "+250 мл")
        XCTAssertNotNil(store.log(identifier: "wt.reminder.2026-10-01.0942"), "журнал знає про заплановане")
    }

    /// Однаковий план не переписує запити; зміна знімає зайве й додає нове (§16.2, п. 4).
    func testRescheduleIsADiff() async {
        await service.rescheduleNow()
        let added = center.addCount
        await service.rescheduleNow()
        XCTAssertEqual(center.addCount, added, "нічого не змінилось — нічого не додано")

        intake(250, at: Fixture.date(10))
        await service.rescheduleNow()
        XCTAssertFalse(scheduledIds.contains("wt.reminder.2026-10-01.0942"), "старий ланцюг знято")
        XCTAssertTrue(scheduledIds.contains("wt.reminder.2026-10-01.1127"), "новий — від порції")
        XCTAssertNotNil(store.log(identifier: "wt.reminder.2026-10-01.1157")?.fireAt)
        XCTAssertNotNil(store.log(identifier: "wt.reminder.2026-10-01.1212")?.cancelledAt, "скасоване лишається в журналі")
    }

    /// Без дозволу нічого не планується, а заплановане знімається (критерій §19.2).
    func testNothingIsScheduledWithoutPermission() async {
        await service.rescheduleNow()
        XCTAssertFalse(scheduledIds.isEmpty)
        center.status = .denied
        await service.rescheduleNow()
        XCTAssertTrue(scheduledIds.isEmpty)
        XCTAssertEqual(service.authorization, .denied)
    }

    func testMasterSwitchOffClearsEverything() async {
        await service.rescheduleNow()
        profiles.profile().notificationsEnabled = false
        await service.rescheduleNow()
        XCTAssertTrue(scheduledIds.isEmpty)
    }

    /// Відлуння додається поза планом — дифф його не знімає.
    func testEchoSurvivesReschedule() async {
        await service.rescheduleNow()
        await service.sendEcho(title: "🎉 Рівень 3", body: "Відкрито щойно", route: .progress, intakeId: UUID(), at: clock.now)
        await service.rescheduleNow()
        XCTAssertTrue(scheduledIds.contains { $0.hasPrefix("wt.echo.2026-10-01.") })
    }

    func testEchoRespectsItsSwitch() async {
        await service.rescheduleNow()
        service.settings.echoEnabled = false
        await service.sendEcho(title: "🎉 Рівень 3", body: "", route: .progress, intakeId: UUID(), at: clock.now)
        XCTAssertFalse(scheduledIds.contains { $0.hasPrefix("wt.echo.") })
    }

    /// «Доставлено» позначається при переплануванні й не подвоюється (§16.8, §16.9).
    func testDeliveredIsMarkedOnceWithMetric() async {
        await service.rescheduleNow()
        clock.set(Fixture.date(10))
        await service.rescheduleNow()
        await service.rescheduleNow()
        XCTAssertNotNil(store.log(identifier: "wt.reminder.2026-10-01.0942")?.deliveredAt)
        XCTAssertEqual(metrics.events(.notificationDelivered).count, 2, "ранкова склянка 08:00 і нагадування 09:42")
    }

    /// Порція протягом 60 хв зараховується найсвіжішому доставленому (§3.2).
    func testIntakeIsAttributedToFreshestDelivered() async {
        await service.rescheduleNow()
        intake(250, at: Fixture.date(10, 5))
        let log = store.log(identifier: "wt.reminder.2026-10-01.0942")!
        XCTAssertEqual(log.response, .intake)
        XCTAssertEqual(metrics.events(.reminderResponded).first?.value, 23, "хвилини від доставки")
        XCTAssertNil(store.log(identifier: "wt.morning.2026-10-01")?.respondedAt, "лише одному — найсвіжішому")
    }

    func testLateIntakeIsNotAttributed() async {
        await service.rescheduleNow()
        // Останнє доставлене — повторне 10:12; 11:15 — уже за межею 60 хв.
        intake(250, at: Fixture.date(11, 15))
        XCTAssertTrue(metrics.events(.reminderResponded).isEmpty, "через 63 хв — уже не відповідь")
    }

    func testSuppressedIsNeverAttributed() async {
        await service.rescheduleNow()
        service.markSuppressed(identifier: "wt.reminder.2026-10-01.0942", at: Fixture.date(9, 42))
        intake(250, at: Fixture.date(10))
        XCTAssertNil(store.log(identifier: "wt.reminder.2026-10-01.0942")?.respondedAt)
    }

    /// Дія «+склянка» відповідає саме своєму сповіщенню; повтор порцію не дублює (критерій §19.7).
    func testActionAttributionAndIdempotency() async {
        await service.rescheduleNow()
        let id = "wt.morning.2026-10-01"
        XCTAssertFalse(service.isIntakeResponded(id))
        intake(250, at: Fixture.date(10, 5), override: id)
        XCTAssertTrue(service.isIntakeResponded(id))
        XCTAssertNil(store.log(identifier: "wt.reminder.2026-10-01.0942")?.respondedAt)
    }

    /// Після порції доставлені нагадування прибираються з Центру сповіщень (критерій §19.6).
    func testDeliveredRemindersAreRemovedAfterIntake() async {
        await service.rescheduleNow()
        intake(250, at: Fixture.date(10, 30))
        await service.rescheduleNow()
        XCTAssertTrue(center.removedDelivered.contains("wt.reminder.2026-10-01.0942"))
        XCTAssertTrue(center.removedDelivered.contains("wt.morning.2026-10-01"))
    }

    func testSnoozeAndPause() async {
        await service.rescheduleNow()
        clock.set(Fixture.date(9, 43))
        service.snooze(identifier: "wt.reminder.2026-10-01.0942", at: clock.now)
        await service.rescheduleNow()
        XCTAssertTrue(scheduledIds.contains("wt.reminder.2026-10-01.1043"), "одне основне через годину")
        XCTAssertEqual(metrics.events(.notificationSnoozed).count, 1)

        service.pause(identifier: "wt.reminder.2026-10-01.1043", at: clock.now)
        await service.rescheduleNow()
        XCTAssertFalse(scheduledIds.contains { $0.hasPrefix("wt.reminder.2026-10-01") })
        XCTAssertTrue(service.isPaused(at: clock.now))
        service.resume()
        XCTAssertFalse(service.isPaused(at: clock.now))
    }

    func testPresentationWhileAppIsOpen() {
        XCTAssertEqual(NotificationService.presentation(forIdentifier: "wt.reminder.2026-10-01.0942"), .suppress)
        XCTAssertEqual(NotificationService.presentation(forIdentifier: "wt.morning.2026-10-01"), .suppress)
        XCTAssertEqual(NotificationService.presentation(forIdentifier: "wt.evening.2026-10-01"), .suppress)
        XCTAssertEqual(NotificationService.presentation(forIdentifier: "wt.rescue.2026-10-01.pm"), .banner)
        XCTAssertEqual(NotificationService.presentation(forIdentifier: "wt.comeback.2026-10-04.1"), .banner)
        XCTAssertEqual(NotificationService.presentation(forIdentifier: "wt.echo.2026-10-01.ab12cd34"), .banner)
    }

    // MARK: - Дозвіл (§16.5)

    func testPermissionPromptFlow() async {
        center.status = .notDetermined
        XCTAssertFalse(service.shouldOfferPermission(at: clock.now), "до першої перевірки статусу — ні")
        await service.refreshAuthorization()
        XCTAssertTrue(service.shouldOfferPermission(at: clock.now))
        XCTAssertEqual(center.authorizationRequests, 0, "на першому запуску системного запиту немає")

        service.postponePermissionPrompt(at: clock.now)
        XCTAssertFalse(service.shouldOfferPermission(at: Fixture.date(day: 3, 10)))
        XCTAssertTrue(service.shouldOfferPermission(at: Fixture.date(day: 4, 10)), "через 3 дні — ще раз")

        service.postponePermissionPrompt(at: Fixture.date(day: 4, 10))
        XCTAssertFalse(service.shouldOfferPermission(at: Fixture.date(day: 20, 10)), "вдруге — лише з налаштувань")
    }

    func testRequestAuthorizationFinishesThePrompt() async {
        center.status = .notDetermined
        await service.refreshAuthorization()
        let granted = await service.requestAuthorization()
        XCTAssertTrue(granted)
        XCTAssertEqual(service.authorization, .authorized)
        XCTAssertFalse(service.shouldOfferPermission(at: clock.now))
    }

    /// Звук — окремо від `soundEnabled` у профілі (критерій §19.18).
    func testSoundIgnoresInAppSoundSwitch() async {
        profiles.profile().soundEnabled = false
        await service.rescheduleNow()
        XCTAssertEqual(center.scheduled.first?.sound, .systemDefault, "булькання без ассету — системний")
        service.settings.sound = .silent
        await service.rescheduleNow()
        XCTAssertEqual(center.scheduled.first?.sound, NotificationSoundSpec.none)
    }
}

final class SchedulerTests: XCTestCase {
    func testFloatingAndAbsoluteTriggers() {
        let plan = NotificationPlanner.plan(context: Fixture.context(at: Fixture.date(7)), preferences: .default)
        let requests = NotificationScheduler.requests(for: plan, sound: .systemDefault, calendar: .kyiv)
        let morning = requests.first { $0.identifier == "wt.morning.2026-10-01" }!
        let reminder = requests.first { $0.identifier == "wt.reminder.2026-10-01.0942" }!
        guard case .calendar(let floating, true) = morning.trigger, case .calendar(let absolute, false) = reminder.trigger else {
            return XCTFail("тригери")
        }
        XCTAssertNil(floating.timeZone, "ранкова склянка йде за поясом пристрою")
        XCTAssertEqual(absolute.timeZone, Fixture.kyiv, "нагадування — абсолютний момент")
        XCTAssertEqual(reminder.userInfo[UserInfoKey.route], "custom:250")
        XCTAssertEqual(reminder.categoryId, "REMINDER")
    }

    func testSoundResolver() {
        XCTAssertEqual(SoundResolver.resolve(.bubble, bubbleAvailable: true), .named("drop.caf"))
        XCTAssertEqual(SoundResolver.resolve(.bubble, bubbleAvailable: false), .systemDefault)
        XCTAssertEqual(SoundResolver.resolve(.system, bubbleAvailable: true), .systemDefault)
        XCTAssertEqual(SoundResolver.resolve(.silent, bubbleAvailable: true), NotificationSoundSpec.none)
    }

    func testTapRouteRoundTrip() {
        for route: NotificationTapRoute in [.home, .customAmount(ml: 350), .freezeCard, .boostCard, .achievement(key: "first.drop"), .progress] {
            XCTAssertEqual(NotificationTapRoute(encoded: route.encoded), route)
        }
    }
}
