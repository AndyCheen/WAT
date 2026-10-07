import XCTest
import Persistence
@testable import Hydration

/// Крок кнопок порцій (WAT-45): до 1 л — 50 мл, від 1 л — 100 мл.
final class PresetRulesTests: XCTestCase {
    func testFineStepBelowOneLiter() {
        XCTAssertEqual(PresetRules.stepped(500, up: true), 550)
        XCTAssertEqual(PresetRules.stepped(950, up: true), 1000)
        XCTAssertEqual(PresetRules.stepped(1000, up: false), 950, "униз з 1 л — знову по 50")
    }

    func testCoarseStepFromOneLiter() {
        XCTAssertEqual(PresetRules.stepped(1000, up: true), 1100)
        XCTAssertEqual(PresetRules.stepped(1100, up: false), 1000)
        XCTAssertEqual(PresetRules.stepped(1900, up: true), 2000)
    }

    /// Значення поза сіткою стає на найближчий вузол у бік кроку.
    func testOffGridValueSnapsToGrid() {
        XCTAssertEqual(PresetRules.stepped(1050, up: true), 1100)
        XCTAssertEqual(PresetRules.stepped(1050, up: false), 1000)
        XCTAssertEqual(PresetRules.stepped(230, up: true), 250)
        XCTAssertEqual(PresetRules.stepped(230, up: false), 200)
    }

    func testStaysWithinIntakeBounds() {
        XCTAssertEqual(PresetRules.stepped(Intake.minAmountMl, up: false), Intake.minAmountMl)
        XCTAssertEqual(PresetRules.stepped(Intake.maxAmountMl, up: true), Intake.maxAmountMl)
    }
}
