import XCTest
import SwiftData
import Core
import Persistence
@testable import Features

/// Звіти з 4a (WAT-67): лише періоди з порціями, щоб і без сповіщень звіт був досяжний.
@MainActor
final class StatsReportsFeatureTests: XCTestCase {
    func testReportLinksOnlyForPeriodsWithData() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 14; parts.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let clock = FixedClock(now: calendar.date(from: parts)!, timeZone: calendar.timeZone)
        let services = AppServices(container: Database.makeInMemoryContainer(), clock: clock)
        services.bootstrap()
        XCTAssertTrue(StatsViewModel(services: services).reportLinks.isEmpty, "без порцій — без звітів")

        clock.set(clock.now.addingTimeInterval(-86_400))
        _ = services.hydration.addIntake(amountMl: 500)
        clock.set(clock.now.addingTimeInterval(86_400))
        let links = StatsViewModel(services: services).reportLinks
        XCTAssertEqual(links.map(\.title), ["Вчора"], "минулий тиждень і місяць — ще без порцій")
        XCTAssertEqual(links.first?.period, .day(DayKey(rawValue: "2026-10-13")))
    }
}
