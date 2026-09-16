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
    /// Якір вікна — перший день з `met`; дні з `partial` на нього не впливають.
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

    /// Те саме, але повертає модель — для сценаріїв, де перевіряємо індикатор серії.
    private func model(today: Int, met: [Int]) -> HomeViewModel {
        let services = AppServices(
            container: Database.makeInMemoryContainer(),
            clock: FixedClock(now: Self.date(day: today, hour: 21))
        )
        services.bootstrap()
        for day in met.sorted() {
            for _ in 0..<4 { services.hydration.addIntake(amountMl: 500, at: Self.date(day: day, hour: 9)) }
        }
        return HomeViewModel(services: services)
    }

    /// Почав у середу й одразу закрив норму.
    func testFirstDayWithGoalMet() {
        XCTAssertEqual(dots(today: 15, met: [15]), "XOOOOOO")
    }

    /// У перший день пив, але норму не добрав, закрив лише другого.
    /// Рядок починається з першого **закритого** дня, а не з першого дня з даними.
    func testAnchorIsFirstDayWithGoalMet() {
        XCTAssertEqual(dots(today: 16, met: [16], partial: [15]), "XOOOOOO")
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

    /// Сім днів поспіль: усі крапки залиті, тож замість них показуємо число серії.
    func testSevenInARowSwitchesToStreakDrop() {
        let model = model(today: 21, met: Array(15...21))
        XCTAssertEqual(model.weekDots.map { $0 ? "X" : "O" }.joined(), "XXXXXXX")
        XCTAssertEqual(model.streakIndicator, .streak(7))
    }

    /// Наступний день після сьомого ще не закритий — крапля лишається з числом 7 (WAT-10).
    /// Повернення крапок щоранку мигало б: серія жива, показувати її «недосягнутою» нема за що.
    func testOpenDayAfterSevenKeepsStreakDrop() {
        let model = model(today: 22, met: Array(15...21))
        XCTAssertEqual(model.streakIndicator, .streak(7))
    }

    /// Восьмий день закрито — число росте.
    func testEighthDayIncrementsStreak() {
        let model = model(today: 22, met: Array(15...22))
        XCTAssertEqual(model.streakIndicator, .streak(8))
    }

    /// Серію зірвано: крапля знову стає крапками. Передостання порожня — вчора норму
    /// не закрито, остання порожня — сьогодні день ще відкритий.
    func testBrokenStreakFallsBackToDots() {
        let model = model(today: 23, met: Array(15...21))
        XCTAssertEqual(model.streakIndicator, .dots(model.weekDots))
        XCTAssertEqual(model.weekDots.map { $0 ? "X" : "O" }.joined(), "XXXXXOO")
    }

    /// Шість днів поспіль до порога не дотягують — крапки лишаються.
    func testSixInARowStillShowsDots() {
        let model = model(today: 20, met: Array(15...20))
        XCTAssertEqual(model.streakIndicator, .dots(model.weekDots))
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
