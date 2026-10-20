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

    /// Години блоку (WAT-58): «дп / пп» один раз, коли обидві межі в одній половині доби.
    func testHourRange() {
        XCTAssertEqual(TimeFormat.hours24.hourRange(8 * 60, 12 * 60), "08–12")
        XCTAssertEqual(TimeFormat.hours24.hourRange(18 * 60, 24 * 60), "18–00")
        XCTAssertEqual(TimeFormat.hours12.hourRange(8 * 60, 11 * 60 + 30), "8–11 дп")
        XCTAssertEqual(TimeFormat.hours12.hourRange(11 * 60, 16 * 60), "11 дп–4 пп")
        XCTAssertEqual(TimeFormat.hours12.hourRange(12 * 60, 18 * 60), "12–6 пп")
        XCTAssertEqual(TimeFormat.hours12.hourRange(18 * 60, 24 * 60), "6 пп–12 дп")
    }

    /// Вага словом (WAT-58): фунти узгоджуються з числом, кілограми — скорочено.
    func testMassLabel() {
        XCTAssertEqual(MassUnit.kilograms.label(70.4), "70 кг")
        XCTAssertEqual(MassUnit.pounds.label(70), "154 фунти")
        XCTAssertEqual(MassUnit.pounds.label(Mass.kilograms(151, from: .pounds)), "151 фунт")
        XCTAssertEqual(MassUnit.pounds.label(Mass.kilograms(165, from: .pounds)), "165 фунтів")
    }

    func testPoundsRoundTrip() {
        for pounds in 66...441 {
            XCTAssertEqual(Mass.display(Mass.kilograms(pounds, from: .pounds), in: .pounds), pounds)
        }
        XCTAssertEqual(Mass.kilograms(70, from: .kilograms), 70)
    }
}
