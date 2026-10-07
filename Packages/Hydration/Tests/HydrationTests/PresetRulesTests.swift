import XCTest
import Persistence
@testable import Hydration

final class PresetRulesTests: XCTestCase {
    func testStepsByDelta() {
        XCTAssertEqual(PresetRules.stepped(200, by: 50, taken: []), 250)
        XCTAssertEqual(PresetRules.stepped(200, by: -50, taken: []), 150)
    }

    func testSkipsTakenValuesInARow() {
        XCTAssertEqual(PresetRules.stepped(200, by: 50, taken: [250, 300]), 350)
        XCTAssertEqual(PresetRules.stepped(400, by: -50, taken: [350, 300]), 250)
    }

    func testStaysWhenNoFreeValueInDirection() {
        XCTAssertEqual(PresetRules.stepped(Intake.minAmountMl, by: -50, taken: []), Intake.minAmountMl)
        XCTAssertEqual(PresetRules.stepped(1950, by: 50, taken: [2000]), 1950, "вільного вгору немає")
    }
}
