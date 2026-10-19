import XCTest
@testable import Core

/// Формат часу (WAT-56): 12-годинний — «дп / пп», як у системній українській локалі.
final class TimeFormatTests: XCTestCase {
    func testTwentyFourHours() {
        XCTAssertEqual(TimeFormat.hours24.clock(7 * 60 + 5), "07:05")
        XCTAssertEqual(TimeFormat.hours24.clock(24 * 60), "24:00")
    }

    func testTwelveHours() {
        XCTAssertEqual(TimeFormat.hours12.clock(0), "12:00 дп")
        XCTAssertEqual(TimeFormat.hours12.clock(7 * 60 + 30), "7:30 дп")
        XCTAssertEqual(TimeFormat.hours12.clock(12 * 60), "12:00 пп")
        XCTAssertEqual(TimeFormat.hours12.clock(22 * 60 + 30), "10:30 пп")
        // Відбій опівночі — кінець доби застосунку.
        XCTAssertEqual(TimeFormat.hours12.clock(24 * 60), "12:00 дп")
    }

    func testPoundsRoundTrip() {
        for pounds in 66...441 {
            XCTAssertEqual(Mass.display(Mass.kilograms(pounds, from: .pounds), in: .pounds), pounds)
        }
        XCTAssertEqual(Mass.kilograms(70, from: .kilograms), 70)
    }
}
