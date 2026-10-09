import XCTest
import SwiftData
import Core
import Persistence
import Gamification
import Notifications
import Widgets
@testable import Features

/// Віджети в композиційному корені: порція ззовні, «Скасувати», знімок, переходи (WAT-30, SPEC-WIDGETS §4, §9).
@MainActor
final class WidgetsFeatureTests: XCTestCase {
    private final class Reloader: WidgetReloading {
        var count = 0
        func reloadAll() { count += 1 }
    }

    private var center: InMemoryNotificationCenter!
    private var clock: FixedClock!
    private var services: AppServices!
    private var store: WidgetSnapshotStore!
    private var reloader: Reloader!
    private var directory: URL!

    /// 1 жовтня 2026, 10:00 за Києвом.
    private static func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute))!
    }

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = WidgetSnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
        reloader = Reloader()
        center = InMemoryNotificationCenter()
        clock = FixedClock(now: Self.date(10))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock, notificationCenter: center,
                               widgetStore: store, widgetReloader: reloader)
        services.bootstrap()
        await services.notifications.rescheduleNow()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    /// Знімок з'являється вже після старту — віджет не лишається «Відкрий застосунок».
    func testSnapshotIsPublishedAfterBootstrap() throws {
        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.day, services.calendar.today)
        XCTAssertEqual(snapshot.goalMl, 2000)
        XCTAssertEqual(snapshot.homeButtons, services.hydration.quickAddAmounts())
        XCTAssertTrue(snapshot.portions.isEmpty)
        XCTAssertNil(snapshot.reserve)
        XCTAssertGreaterThan(reloader.count, 0)
    }

    /// Порція з віджета: джерело `.widget`, у знімку — порція, «Скасувати» і запас до нагадування з плану.
    func testAddFromWidget() async throws {
        await services.perform(.add(ml: 250, source: .widget)).value

        let intakes = services.dayLogs.activeIntakes(for: services.calendar.today)
        XCTAssertEqual(intakes.map(\.amountMl), [250])
        XCTAssertEqual(intakes.first?.source, .widget)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.portions.map(\.ml), [250])
        XCTAssertEqual(snapshot.lastAction?.intakeId, intakes.first?.id)

        let reserve = try XCTUnwrap(snapshot.reserve)
        let reminder = services.notifications.lastPlan.items
            .filter { $0.type == .reminder || $0.type == .checkpoint }.map(\.fireAt).min()
        XCTAssertEqual(reserve.reminderAt, reminder, "нуль — за 10 хв до нагадування з плану")
        XCTAssertTrue(reserve.reminderIsPlanned)
        XCTAssertEqual(reserve.zeroAt, reminder?.addingTimeInterval(-HydrationReserve.reminderLead))
        XCTAssertEqual(reserve.anchorMl, 250)
    }

    /// «Команди» пишуть своє джерело — щоб потім було видно, звідки вносять воду (ТЗ §2).
    func testShortcutSource() async {
        await services.perform(.add(ml: 500, source: .shortcut)).value
        XCTAssertEqual(services.dayLogs.activeIntakes(for: services.calendar.today).first?.source, .shortcut)
    }

    /// Порція з віджета, поки застосунку немає на екрані, — відлуння розблокувань (SPEC-NOTIFICATIONS §12.1).
    func testEchoOutsideTheApp() async {
        await services.perform(.add(ml: 250, source: .widget)).value
        XCTAssertEqual(center.scheduled.first { $0.identifier.hasPrefix("wt.echo.") }?.title, "🏅 Досягнення: Перша крапля")
    }

    func testNoEchoWhileAppIsOpen() async {
        services.handleBecameActive()
        await services.perform(.add(ml: 250, source: .widget)).value
        XCTAssertFalse(center.scheduled.contains { $0.identifier.hasPrefix("wt.echo.") })
    }

    /// «Скасувати» прибирає порцію й відкочує XP так само, як видалення з історії.
    func testUndoRemovesPortionAndXp() async throws {
        let xpBefore = services.gamification.levelProgress().totalXp
        await services.perform(.add(ml: 250, source: .widget)).value
        XCTAssertGreaterThan(services.gamification.levelProgress().totalXp, xpBefore)
        let id = try XCTUnwrap(services.lastWidgetAction?.intakeId)

        await services.perform(.undo(intakeId: id)).value

        XCTAssertTrue(services.dayLogs.activeIntakes(for: services.calendar.today).isEmpty)
        XCTAssertEqual(services.gamification.levelProgress().totalXp, xpBefore)
        let snapshot = try XCTUnwrap(store.read())
        XCTAssertNil(snapshot.lastAction)
        XCTAssertNil(snapshot.reserve)
    }

    /// Старий таймлайн не прибирає порцію, яку додали не з віджета.
    func testUndoOnlyForWidgetPortion() async {
        await services.perform(.add(ml: 250, source: .widget)).value
        let other = services.hydration.addIntake(amountMl: 300)
        services.touch()

        await services.perform(.undo(intakeId: other!.intakeId)).value

        XCTAssertEqual(services.dayLogs.activeIntakes(for: services.calendar.today).count, 2)
    }

    func testSimulatedActionsForUITests() async {
        await services.simulateWidgetActions("add:250,add:500,undo")
        XCTAssertEqual(services.dayLogs.activeIntakes(for: services.calendar.today).map(\.amountMl), [250])
    }

    /// Той самий зміст — таймлайни не перезавантажуються: бюджет оновлень у фоні обмежений.
    func testUnchangedSnapshotDoesNotReload() async {
        let before = reloader.count
        await services.notifications.rescheduleNow()
        XCTAssertEqual(reloader.count, before)
        await services.perform(.add(ml: 250, source: .widget)).value
        XCTAssertGreaterThan(reloader.count, before)
    }

    /// Інтент повертається, щойно порцію записано: знімок уже з нею, хоча перепланування ще не дійшло, — так
    /// цифра на віджеті змінюється без очікування на сповіщення. Час нагадування приходить другим знімком.
    func testSnapshotIsWrittenBeforeRescheduling() async throws {
        let followUp = await services.perform(.add(ml: 250, source: .widget))

        let early = try XCTUnwrap(store.read())
        XCTAssertEqual(early.portions.map(\.ml), [250])
        XCTAssertNotNil(early.lastAction)
        XCTAssertEqual(early.reserve?.reminderIsPlanned, false, "старий план — ще до порції")

        await followUp.value
        XCTAssertEqual(store.read()?.reserve?.reminderIsPlanned, true)
    }

    /// Таймлайни перезавантажує хвіст дії, а не `perform()`: натиснутий віджет WidgetKit перезавантажує сам
    /// одразу після інтенту, і прохання «перезавантаж усе» раніше за це ставило б його в кінець черги.
    func testReloadWaitsForActionTail() async {
        let before = reloader.count
        let followUp = await services.perform(.add(ml: 250, source: .widget))
        XCTAssertEqual(reloader.count, before)

        // Чужий прохід перепланування посеред дії (стартовий на холодному запуску) теж чекає.
        services.touch()
        await followUp.value
        XCTAssertEqual(reloader.count, before + 1)
    }

    /// Відкриття застосунку відсуває нагадування на 30 хв — крапля не підстрибує, змінюється лише нахил.
    func testReserveDoesNotJumpWhenReminderMoves() async throws {
        await services.perform(.add(ml: 250, source: .widget)).value
        let first = try XCTUnwrap(store.read()?.reserve)
        clock.set(Self.date(10, 40))
        let levelBefore = first.level(at: clock.now)

        services.handleBecameActive()
        await services.notifications.rescheduleNow()

        let after = try XCTUnwrap(store.read()?.reserve)
        XCTAssertEqual(after.level(at: clock.now), levelBefore, accuracy: 0.5)
    }

    /// «Інше» у віджеті: підказки — зі шторки «Інше», порція згортає вибір.
    func testCustomPickerFromGallery() async throws {
        await services.perform(.showCustomPicker(.quickAdd)).value
        XCTAssertTrue(services.widgetPicker.isOpen(.quickAdd, at: clock.now))
        XCTAssertEqual(try XCTUnwrap(store.read()).hints, services.hydration.quickAddAmounts(.customSheet))

        await services.perform(.add(ml: 350, source: .widget)).value
        XCTAssertFalse(services.widgetPicker.isOpen(.quickAdd, at: clock.now))

        await services.perform(.showCustomPicker(.overview)).value
        await services.perform(.hideCustomPicker(.overview)).value
        XCTAssertFalse(services.widgetPicker.isOpen(.overview, at: clock.now))
    }

    func testLinks() {
        services.open(.stats)
        XCTAssertEqual(services.router.takePath(), [.stats])
        services.open(.progress)
        XCTAssertEqual(services.router.takePath(), [.progress])
        services.open(.custom)
        XCTAssertEqual(services.router.takePath(), [])
        XCTAssertEqual(services.router.takeHomeIntent(), .customAmount(services.hydration.customAmountStart()))
    }
}
