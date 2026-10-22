import XCTest
import SwiftData
import Core
import Persistence
import Gamification
import Hydration
import Notifications
@testable import Features

/// Досягнення, умови яких залежать від точного об'єму, можна виконати з інтерфейсу — тими самими викликами,
/// що й шторка «Інше» (WAT-50, SPEC-ACHIEVEMENTS-CATALOG §9). Без точного вводу кнопки, віджети й степер дають лише
/// сітку 50 мл: 314 мл на ній немає, а чотиризначного паліндрома, кратного 50, не існує.
@MainActor
final class AchievementReachabilityTests: XCTestCase {
    private var services: AppServices!
    private var clock: FixedClock!
    private var calendar = Calendar(identifier: .gregorian)

    override func setUp() async throws {
        try await super.setUp()
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        clock = FixedClock(now: date(day: 1, hour: 10))
        services = AppServices(container: Database.makeInMemoryContainer(), clock: clock,
                               notificationCenter: InMemoryNotificationCenter())
        services.bootstrap()
    }

    private func date(day: Int, hour: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = day; parts.hour = hour
        return calendar.date(from: parts)!
    }

    private func isUnlocked(_ key: String) -> Bool {
        services.gamification.achievementSnapshots().first { $0.key == key }?.isUnlocked ?? false
    }

    /// Набрати на клавіатурі шторки «Інше» й натиснути «Додати».
    private func type(_ text: String, on home: HomeViewModel) {
        home.openCustom()
        home.beginCustomTyping()
        home.typeCustom(text)
        home.confirmCustom()
    }

    func testFiftyGridHasNoFourDigitPalindrome() {
        let grid = stride(from: 1000, through: 9999, by: VolumeSteps.custom(.milliliters).fine)
        XCTAssertFalse(grid.contains { String($0) == String(String($0).reversed()) },
                       "інакше точний ввід для «Дзеркала» був би не потрібен")
        XCTAssertNotEqual(314 % VolumeSteps.custom(.milliliters).fine, 0)
    }

    func testPiIsReachableByTypingTheAmount() {
        let home = HomeViewModel(services: services)
        home.openCustom()
        home.confirmCustom()                         // 300 — «Перша крапля» й «Своя мірка» окремим вікном
        services.dismissCelebration()

        type("314", on: home)
        XCTAssertTrue(isUnlocked("egg.pi"))
        XCTAssertEqual(services.celebration?.pages.first?.title, "Пі")
        XCTAssertEqual(services.celebration?.pages.first?.label, "Пасхалка")
    }

    /// 1800 кнопками головного й 312 з клавіатури — 2112 мл. День ще триває, тож «Дзеркало» відкривається
    /// наступного ранку, вікном «Поки тебе не було» на відкритті застосунку.
    func testMirrorIsReachableWithOneTypedPortion() {
        let home = HomeViewModel(services: services)
        home.add(1000)
        home.add(500)
        home.add(300)
        type("312", on: home)
        XCTAssertEqual(services.hydration.todaySnapshot().totalMl, 2112)
        XCTAssertFalse(isUnlocked("special.mirror"), "доливання ще може зіпсувати паліндром")
        _ = celebratedTitles()                       // вікна за перші порції дня

        clock.set(date(day: 2, hour: 9))
        services.handleBecameActive()
        XCTAssertTrue(isUnlocked("special.mirror"))
        XCTAssertEqual(services.celebration?.context, .whileAway)
        XCTAssertTrue(celebratedTitles().contains("Дзеркало"))
    }

    /// Закрити всі вікна відкриття поспіль, як людина «Чудово», — назви їхніх сторінок.
    private func celebratedTitles() -> [String] {
        var titles: [String] = []
        for _ in 0..<10 {
            guard let shown = services.celebration else { break }
            titles += shown.pages.map(\.title)
            services.dismissCelebration()
        }
        XCTAssertNil(services.celebration, "вікна відкриття не закінчились")
        return titles
    }
}
