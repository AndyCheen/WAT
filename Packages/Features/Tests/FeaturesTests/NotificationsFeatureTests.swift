import XCTest
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
@testable import Features

/// Сповіщення в композиційному корені: дії, відлуння, переходи, дозвіл (SPEC-NOTIFICATIONS §16.4, §19).
@MainActor
final class NotificationsFeatureTests: XCTestCase {
    private var center: InMemoryNotificationCenter!
    private var clock: FixedClock!
    private var services: AppServices!

    /// 1 жовтня 2026, 10:00 за Києвом.
    private static func date(day: Int = 1, _ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = day; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: parts)!
    }

    override func setUp() async throws {
        try await super.setUp()
        center = InMemoryNotificationCenter()
        clock = FixedClock(now: Self.date(10))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center)
        services.bootstrap()
        await services.notifications.rescheduleNow()
    }

    private var firstReminder: String {
        services.notifications.lastPlan.items.first { $0.type == .reminder }!.id
    }

    private func respond(_ action: NotificationResponseInfo.Action, to identifier: String,
                         userInfo: [String: String] = [UserInfoKey.glassMl: "300"]) async {
        await services.handleNotificationResponse(NotificationResponseInfo(identifier: identifier, action: action, userInfo: userInfo))
    }

    /// На першому запуску системного запиту немає (критерій §19.1).
    func testBootstrapDoesNotRequestAuthorization() {
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertFalse(center.scheduled.isEmpty, "у тестовому центрі дозвіл уже є — план у центрі")
    }

    /// «+склянка» додає порцію з `source = .notification`, повторна відповідь її не дублює (критерій §19.7).
    func testAddGlassActionIsIdempotent() async {
        let id = firstReminder
        clock.set(Self.date(11, 30))
        await respond(.addGlass, to: id)
        await respond(.addGlass, to: id)

        let intakes = services.dayLogs.activeIntakes(for: services.calendar.today)
        XCTAssertEqual(intakes.map(\.amountMl), [300], "об'єм — з дії сповіщення, а не з поточного налаштування")
        XCTAssertEqual(intakes.first?.source, .notification)
        XCTAssertTrue(services.notifications.isIntakeResponded(id))
    }

    /// Відкрите порцією з дії досягнення приходить сповіщенням, бо застосунку на екрані немає.
    func testEchoForUnlockOutsideTheApp() async {
        await respond(.addGlass, to: firstReminder)
        let echo = center.scheduled.first { $0.identifier.hasPrefix("wt.echo.2026-10-01.") }
        XCTAssertEqual(echo?.title, "🏅 Досягнення: Перша крапля")
        XCTAssertEqual(echo?.trigger, .immediate)
    }

    /// Поки застосунок відкритий, розблокування показує тост — сповіщення його лише дублювало б.
    func testNoEchoWhileAppIsOpen() async {
        services.handleBecameActive()
        await respond(.addGlass, to: firstReminder)
        XCTAssertFalse(center.scheduled.contains { $0.identifier.hasPrefix("wt.echo.") })
    }

    func testTapRoutes() async {
        await respond(.open, to: "wt.rescue.2026-10-01.pm", userInfo: [UserInfoKey.route: "freeze"])
        XCTAssertEqual(services.router.takePath(), [.prizeCard(RewardCatalog.freezeKey)])

        await respond(.otherAmount, to: firstReminder, userInfo: [UserInfoKey.portionMl: "350"])
        XCTAssertEqual(services.router.takePath(), [])
        XCTAssertEqual(services.router.takeHomeIntent(), .customAmount(350))

        services.simulateNotificationTap(.reminder)
        XCTAssertEqual(services.router.takeHomeIntent(), .customAmount(250), "без історії P = моя склянка")
        services.simulateNotificationTap(.echo)
        XCTAssertEqual(services.router.takePath(), [.progress])
    }

    func testSnoozeAndPauseFromTheNotification() async {
        clock.set(Self.date(10, 5))
        await respond(.pause, to: firstReminder)
        XCTAssertTrue(services.notifications.isPaused(at: clock.now))
        XCTAssertFalse(center.scheduled.contains { $0.identifier.hasPrefix("wt.reminder.2026-10-01") })
    }

    /// Відкриття застосунку — дія: ланцюг нагадувань стартує не раніше ніж через 30 хв.
    func testBecomingActiveRecordsInteraction() async {
        clock.set(Self.date(12))
        services.handleBecameActive()
        await services.notifications.rescheduleNow()
        XCTAssertEqual(services.notifications.settings.lastInteractionAt, Self.date(12))
        let first = services.notifications.lastPlan.items.first { $0.type == .reminder && $0.dayKey.day == 1 }
        XCTAssertGreaterThanOrEqual(first!.fireAt, Self.date(12, 30))
    }

    func testContextReflectsTheDay() {
        services.hydration.addIntake(amountMl: 250, at: Self.date(8))
        services.hydration.addIntake(amountMl: 500, at: Self.date(9, 30))
        let context = services.makeNotificationContext()
        XCTAssertEqual(context.countedMl, 750)
        XCTAssertEqual(context.intakesToday.count, 2)
        XCTAssertEqual(context.portionHistoryMl.sorted(), [250, 500])
        XCTAssertEqual(context.firstIntakeMinutes, [8 * 60])
        XCTAssertEqual(context.lastIntakeAt, Self.date(9, 30))
        XCTAssertEqual(context.goalMl, 2000)
    }

    /// Шторка дозволу — після першої порції й після тоста, не замість нього (§16.5).
    func testPermissionSheetFollowsFirstIntakeToast() async {
        center.status = .notDetermined
        await services.notifications.refreshAuthorization()
        let model = HomeViewModel(services: services)

        model.add(250)
        XCTAssertNotNil(model.toast, "«Перша крапля»")
        XCTAssertNil(model.sheet, "шторка не перекриває тост")

        model.dismissToast()
        XCTAssertEqual(model.sheet?.id, HomeSheet.permission.id)

        model.postponeNotifications()
        model.add(250)
        XCTAssertNil(model.sheet, "«Не зараз» — наступного разу через 3 дні")
    }

    func testUnlockToastPriorities() {
        let gift = RewardSnapshot(id: UUID(), key: RewardCatalog.boostKey, title: "Подвійний XP", details: "",
                                  emoji: "⚡", kind: .xpBoost, state: .ready, isNew: true,
                                  acquiredAt: clock.now, activatedAt: nil, expiresAt: nil)
        XCTAssertEqual(HomeViewModel.unlockToast(RecentUnlocks(comebackGift: gift), levelUp: 5)?.message,
                       "🎁 З поверненням! ⚡ Подвійний XP — у призах")
        XCTAssertEqual(HomeViewModel.unlockToast(RecentUnlocks(bounceBackXp: 25), levelUp: 5)?.message,
                       "Рівень 5! · 🔁 Знову в ритмі: +25 XP")
        XCTAssertEqual(HomeViewModel.unlockToast(RecentUnlocks(bounceBackXp: 50), levelUp: nil)?.message,
                       "🔁 Знову в ритмі: +50 XP")
        XCTAssertNil(HomeViewModel.unlockToast(.empty, levelUp: nil))
    }
}
