import XCTest
@testable import Core

final class DayPartTests: XCTestCase {
    func testHourMapping() {
        XCTAssertEqual(DayPart.from(hour: 7), .morning)
        XCTAssertEqual(DayPart.from(hour: 10), .noon)
        XCTAssertEqual(DayPart.from(hour: 13), .afternoon)
        XCTAssertEqual(DayPart.from(hour: 20), .evening)
        XCTAssertEqual(DayPart.from(hour: 23), .night)
        XCTAssertEqual(DayPart.from(hour: 3), .night)
    }

    func testIdealSharesSumToOne() {
        let total = DayPart.allCases.reduce(0.0) { $0 + $1.idealShare }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }

    func testEveryHourMapsToExactlyOnePart() {
        for hour in 0..<24 {
            let part = DayPart.from(hour: hour)
            XCTAssertTrue(DayPart.allCases.contains(part), "година \(hour)")
        }
    }
}
