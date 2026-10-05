import XCTest
import SwiftData
import Core
import Persistence
import Notifications
@testable import Features

/// Капсула поточної частини доби на головному (WAT-40). Розклад за замовчуванням — 08:00–22:00,
/// норма 2000 мл: цілі частин 649 (до 12:00), 780 і 571 мл.
@MainActor
final class DayPartFeatureTests: XCTestCase {
    private var clock: FixedClock!
    private var services: AppServices!

    /// 1 жовтня 2026 (четвер), за Києвом.
    private static func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 1; parts.hour = hour; parts.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar.date(from: parts)!
    }

    override func setUp() async throws {
        try await super.setUp()
        clock = FixedClock(now: Self.date(7))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock,
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    private func add(_ ml: Int, at hour: Int, _ minute: Int, to model: HomeViewModel) {
        clock.set(Self.date(hour, minute))
        model.add(ml)
    }

    /// Критерій приймання: 300 + 250 мл до 11:25 — «ще 100 мл» і «35 хв».
    func testAcceptanceScenario() throws {
        let model = HomeViewModel(services: services)
        add(300, at: 9, 10, to: model)
        add(250, at: 10, 40, to: model)
        clock.set(Self.date(11, 25))

        let line = try XCTUnwrap(model.dayPartLine())
        guard case let .pending(fraction, title, xp, timeLeft) = line.content else {
            return XCTFail("очікувалась незакрита частина, а не \(line.content)")
        }
        XCTAssertEqual(title, "До 12:00 — ще 100 мл")
        XCTAssertEqual(xp, "+10 XP")
        XCTAssertEqual(timeLeft, "35 хв")
        XCTAssertEqual(fraction, 550.0 / 649, accuracy: 1e-9)
        XCTAssertEqual(line.accessibilityLabel, "До 12:00 бракує 100 мл, лишилось 35 хвилин")
    }

    /// Порція, що закриває частину, одразу дає ✓; видалення її — повертає «ще N мл».
    func testClosingPortionSwitchesToClosed() throws {
        let model = HomeViewModel(services: services)
        add(300, at: 9, 10, to: model)
        add(250, at: 10, 40, to: model)
        add(250, at: 11, 40, to: model)

        let closed = try XCTUnwrap(model.dayPartLine())
        XCTAssertEqual(closed.content, .closed(title: "Ранок і полудень закрито"))
        XCTAssertEqual(closed.accessibilityLabel, "Ранок і полудень закрито")

        // ✓ тримається до кінця частини, з 12:00 — уже наступна.
        clock.set(Self.date(11, 59))
        XCTAssertEqual(model.dayPartLine()?.content, .closed(title: "Ранок і полудень закрито"))
        clock.set(Self.date(12, 0))
        guard case let .pending(_, title, _, timeLeft) = try XCTUnwrap(model.dayPartLine()).content else {
            return XCTFail("о 12:00 почалась нова частина")
        }
        XCTAssertEqual(title, "До 17:00 — ще 800 мл")
        XCTAssertEqual(timeLeft, "5 год")

        clock.set(Self.date(11, 45))
        model.remove(id: try XCTUnwrap(model.history.first { $0.amountMl == 250 && services.calendar.minuteOfDay($0.createdAt) == 11 * 60 + 40 }).id)
        guard case .pending = try XCTUnwrap(model.dayPartLine()).content else {
            return XCTFail("без закриваючої порції частина знову відкрита")
        }
    }

    func testHiddenOutsideActiveHours() {
        let model = HomeViewModel(services: services)
        clock.set(Self.date(7, 59))
        XCTAssertNil(model.dayPartLine())
        clock.set(Self.date(8))
        XCTAssertNotNil(model.dayPartLine())
        clock.set(Self.date(22))
        XCTAssertNil(model.dayPartLine())
    }

    /// Вечір теж показується: XP за нього нараховується, хоча чекпоінта немає.
    func testEveningIsShown() throws {
        let model = HomeViewModel(services: services)
        clock.set(Self.date(21, 30))
        guard case let .pending(_, title, _, timeLeft) = try XCTUnwrap(model.dayPartLine()).content else {
            return XCTFail("вечір без порцій — незакритий")
        }
        XCTAssertEqual(title, "До 22:00 — ще 600 мл")
        XCTAssertEqual(timeLeft, "30 хв")
    }

    func testHiddenOnceDailyGoalIsMet() {
        let model = HomeViewModel(services: services)
        add(1000, at: 9, 0, to: model)
        add(1000, at: 10, 0, to: model)
        XCTAssertNil(model.dayPartLine())
    }

    /// Новий підйом після першої порції не переносить межі сьогоднішніх цілей — як і XP (WAT-39).
    func testUsesDayScheduleSnapshot() throws {
        let model = HomeViewModel(services: services)
        add(300, at: 9, 0, to: model)
        services.profile.wakeMinutes = 10 * 60
        clock.set(Self.date(11, 0))
        model.reload()
        guard case let .pending(_, title, _, _) = try XCTUnwrap(model.dayPartLine()).content else {
            return XCTFail("частина до 12:00 не закрита")
        }
        XCTAssertEqual(title, "До 12:00 — ще 350 мл")
    }

    // MARK: - Тексти

    func testFormatting() {
        XCTAssertEqual(DayPartPresenter.roundedUp(99), 100)
        XCTAssertEqual(DayPartPresenter.roundedUp(100), 100)
        XCTAssertEqual(DayPartPresenter.roundedUp(101), 150)
        XCTAssertEqual(DayPartPresenter.volume(950), "950 мл")
        XCTAssertEqual(DayPartPresenter.volume(1500), "1.5 л")
        XCTAssertEqual(DayPartPresenter.volume(1050), "1.05 л")
        XCTAssertEqual(DayPartPresenter.volume(2000), "2 л")
        XCTAssertEqual(DayPartPresenter.duration(80), "1 год 20 хв")
        XCTAssertEqual(DayPartPresenter.spokenDuration(61), "1 година 1 хвилина")
        XCTAssertEqual(DayPartPresenter.spokenDuration(22), "22 хвилини")
        XCTAssertEqual(DayPartPresenter.spokenDuration(120), "2 години")
    }

    /// Буст подвоює XP за ціль частини, відбій опівночі — «00:00».
    func testBoostAndMidnightDeadline() throws {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 24 * 60)
        let progress = curve.dayPartProgress(atMinute: 23 * 60, portions: [])
        let line = try XCTUnwrap(DayPartPresenter.line(progress, goalMet: false, xp: 20))
        guard case let .pending(_, title, xp, _) = line.content else { return XCTFail() }
        XCTAssertTrue(title.hasPrefix("До 00:00 — ще "), title)
        XCTAssertEqual(xp, "+20 XP")
    }
}
