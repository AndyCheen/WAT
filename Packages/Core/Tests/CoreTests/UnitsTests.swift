import XCTest
@testable import Core

final class UnitsTests: XCTestCase {
    func testRoundTripMillilitersToOunces() {
        let oz = Volume.display(500, in: .fluidOunces)
        XCTAssertEqual(oz, 17)
        XCTAssertEqual(Volume.toMilliliters(oz, from: .fluidOunces), 503)
    }

    func testMillilitersPassThrough() {
        XCTAssertEqual(Volume.display(1250, in: .milliliters), 1250)
        XCTAssertEqual(Volume.toMilliliters(1250, from: .milliliters), 1250)
    }

    func testLitersLabelMatchesMockup() {
        // Макет 1a: «1.25 / 2.0 л»
        XCTAssertEqual(Volume.litersLabel(1250), "1.25")
        XCTAssertEqual(Volume.litersLabel(2000, fractionDigits: 1), "2.0")
    }
}
