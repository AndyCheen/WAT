import XCTest
@testable import Core

final class UnitsTests: XCTestCase {
    func testOuncesRoundTrip() {
        XCTAssertEqual(VolumeUnit.usFluidOunces.units(500), 17)
        XCTAssertEqual(VolumeUnit.usFluidOunces.milliliters(units: 8), 237)
        XCTAssertEqual(VolumeUnit.usFluidOunces.units(VolumeUnit.usFluidOunces.milliliters(units: 8)), 8)
    }

    func testMillilitersPassThrough() {
        XCTAssertEqual(VolumeUnit.milliliters.units(1250), 1250)
        XCTAssertEqual(VolumeUnit.milliliters.milliliters(units: 1250), 1250)
    }

    /// Старе значення `volumeUnitRaw = 1` — унції США.
    func testRawValuesKeepOldOunces() {
        XCTAssertEqual(VolumeUnit(rawValue: 1), .usFluidOunces)
    }

    func testFormatKeepsMetricPlaceFormat() {
        XCTAssertEqual(VolumeUnit.milliliters.format(1050) { "\($0) мл" }, "1050 мл")
        XCTAssertEqual(VolumeUnit.usFluidOunces.format(1000) { "\($0) мл" }, "34 унц.")
    }

    /// Крапка позначення не подвоюється в кінці речення.
    func testTidyDropsDoubleDot() {
        XCTAssertEqual(VolumeUnit.tidy("До цілі ще 17 унц.. Почни"), "До цілі ще 17 унц. Почни")
        XCTAssertEqual(VolumeUnit.tidy("До цілі ще 1,5 л. Почни"), "До цілі ще 1,5 л. Почни")
    }

    func testRoundUpNeverLeavesShort() {
        XCTAssertEqual(VolumeUnit.usFluidOunces.unitsRoundedUp(240), 9)
        XCTAssertEqual(VolumeUnit.milliliters.unitsRoundedUp(240), 240)
    }

    /// Крок униз від «8 унц.» (237 мл) — «7 унц.», а не знову «8 унц.».
    func testSteppingStartsFromShownValue() {
        let unit = VolumeUnit.usFluidOunces
        let grid = VolumeGrid(fine: 1, coarse: 2, coarseFrom: 32)
        let eight = unit.milliliters(units: 8)
        XCTAssertEqual(unit.units(unit.stepped(eight, up: false, grid: grid)), 7)
        XCTAssertEqual(unit.units(unit.stepped(eight, up: true, grid: grid)), 9)
        let thirtyTwo = unit.milliliters(units: 32)
        XCTAssertEqual(unit.units(unit.stepped(thirtyTwo, up: true, grid: grid)), 34)
        XCTAssertEqual(unit.units(unit.stepped(thirtyTwo, up: false, grid: grid)), 31)
    }

    func testSnapToNearestGridNode() {
        let grid = VolumeGrid(fine: 50, coarse: 100, coarseFrom: 1000)
        XCTAssertEqual(VolumeUnit.milliliters.snapped(237, grid: grid), 250)
        XCTAssertEqual(VolumeUnit.milliliters.snapped(1040, grid: grid), 1000)
        XCTAssertEqual(VolumeUnit.usFluidOunces.units(VolumeUnit.usFluidOunces.snapped(300, grid: VolumeGrid(step: 1))), 10)
    }

    func testLitersLabelMatchesMockup() {
        // Макет 1a: «1.25 / 2.0 л»
        XCTAssertEqual(Volume.litersLabel(1250), "1.25")
        XCTAssertEqual(Volume.litersLabel(2000, fractionDigits: 1), "2.0")
    }
}
