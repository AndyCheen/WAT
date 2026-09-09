import XCTest
import Core
import Persistence
import Hydration
@testable import Features

/// Сценарії рядка крапок на головному (WAT-11), записані так само, як у задачі:
/// `X` — ціль виконано, `O` — ні (зокрема день, якого ще не було).
///
/// Липень 2026: 15-те — середа, 18-те — субота.
@MainActor
final class WeekDotsTests: XCTestCase {
    private static func date(day: Int, hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = day; c.hour = hour
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    /// Збирає застосунок із заданим «сьогодні» й історією та повертає рядок крапок.
    /// `met` — дні із закритою нормою, `partial` — дні, коли пив, але норму не закрив.
    private func dots(today: Int, met: [Int], partial: [Int] = []) -> String {
        let services = AppServices(
            container: Database.makeInMemoryContainer(),
            clock: FixedClock(now: Self.date(day: today, hour: 21))
        )
        services.bootstrap()

        for day in met.sorted() {
            for _ in 0..<4 { services.hydration.addIntake(amountMl: 500, at: Self.date(day: day, hour: 9)) }
        }
        for day in partial.sorted() {
            services.hydration.addIntake(amountMl: 500, at: Self.date(day: day, hour: 9))
        }

        return HomeViewModel(services: services).weekDots.map { $0 ? "X" : "O" }.joined()
    }

    /// Почав у середу й одразу закрив норму.
    func testFirstDayWithGoalMet() {
        XCTAssertEqual(dots(today: 15, met: [15]), "XOOOOOO")
    }

    /// Середа й четвер поспіль.
    func testTwoDaysInARow() {
        XCTAssertEqual(dots(today: 16, met: [15, 16]), "XXOOOOO")
    }

    /// Середа закрита, четвер пропущено, пʼятниця знову закрита.
    /// Пропуск лишає дірку на своєму місці — крапки не ущільнюються.
    func testGapKeepsItsPosition() {
        XCTAssertEqual(dots(today: 17, met: [15, 17], partial: [16]), "XOXOOOO")
    }

    /// Сім днів поспіль: усі крапки залиті, тож замість них показуємо число.
    func testSevenInARowSwitchesToCount() {
        let services = AppServices(
            container: Database.makeInMemoryContainer(),
            clock: FixedClock(now: Self.date(day: 21, hour: 21))
        )
        services.bootstrap()
        for day in 15...21 {
            for _ in 0..<4 { services.hydration.addIntake(amountMl: 500, at: Self.date(day: day, hour: 9)) }
        }

        let model = HomeViewModel(services: services)
        XCTAssertEqual(model.weekDots.map { $0 ? "X" : "O" }.joined(), "XXXXXXX")
        XCTAssertTrue(model.showsStreakCount)
        XCTAssertEqual(model.streakLabel, "7")
    }

    /// Сім днів поспіль, а наступний день ще не закритий: вікно поїхало, показуємо крапки.
    /// Серія формально жива до кінця доби, тому вмикати число тут не можна.
    func testOpenDayAfterSevenShowsDotsAgain() {
        let services = AppServices(
            container: Database.makeInMemoryContainer(),
            clock: FixedClock(now: Self.date(day: 22, hour: 21))
        )
        services.bootstrap()
        for day in 15...21 {
            for _ in 0..<4 { services.hydration.addIntake(amountMl: 500, at: Self.date(day: day, hour: 9)) }
        }

        let model = HomeViewModel(services: services)
        XCTAssertEqual(model.weekDots.map { $0 ? "X" : "O" }.joined(), "XXXXXXO")
        XCTAssertFalse(model.showsStreakCount, "день ще відкритий — число сховало б, що робити")
    }

    /// Пʼять поспіль, один пропущено, останній закрито.
    func testGapBeforeToday() {
        XCTAssertEqual(dots(today: 21, met: [15, 16, 17, 18, 19, 21], partial: [20]), "XXXXXOX")
    }

    /// Порожня історія — якоря немає, рядок порожній.
    func testEmptyHistory() {
        XCTAssertEqual(dots(today: 18, met: []), "OOOOOOO")
    }
}
