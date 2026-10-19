import XCTest
import Core
@testable import Widgets

/// Віджети в системі людини (WAT-58): унції й 12-годинний формат — зі знімка застосунку. Мілілітри й 24 години
/// тримає `WidgetPresenterTests`: там тексти не змінились.
final class WidgetUnitsTests: XCTestCase {
    private func usSnapshot(_ base: WidgetSnapshot = Fixture.snapshot()) -> WidgetSnapshot {
        var snapshot = base
        snapshot.unitRaw = VolumeUnit.usFluidOunces.rawValue
        snapshot.timeFormatRaw = TimeFormat.hours12.rawValue
        return snapshot
    }

    private func day(_ hour: Int, _ minute: Int, _ snapshot: WidgetSnapshot) -> WidgetDay {
        WidgetDay.resolve(snapshot, at: Fixture.date(hour, minute), calendar: Fixture.calendar)
    }

    func testDayCarriesTheSystemOfTheSnapshot() {
        let us = day(13, 25, usSnapshot())
        XCTAssertEqual(us.unit, .usFluidOunces)
        XCTAssertEqual(us.timeFormat, .hours12)
        let metric = day(13, 25, Fixture.snapshot())
        XCTAssertEqual(metric.unit, .milliliters)
        XCTAssertEqual(metric.timeFormat, .hours24)
    }

    func testVolumeInOunces() {
        let oz = VolumeUnit.usFluidOunces
        XCTAssertEqual(WidgetPresenter.ringVolume(countedMl: 1250, goalMl: 2000, unit: oz), "42 / 68 унц.")
        XCTAssertEqual(WidgetPresenter.amount(237, unit: oz), "8 унц.")
        XCTAssertEqual(WidgetPresenter.addTitle(473, unit: oz), "+16 унц.")
        XCTAssertEqual(WidgetPresenter.left(626, unit: oz), "ще 22 унц.", "вгору до цілої, як капсула")
        XCTAssertEqual(WidgetPresenter.liters(1250, unit: oz), "42")
        XCTAssertEqual(WidgetPresenter.bigUnit(oz), "унц.")
        XCTAssertEqual(WidgetPresenter.number(500, unit: oz), "17")
        XCTAssertEqual(WidgetPresenter.unitWord(500, unit: oz), "унц.")
    }

    /// Частина доби: число й позначення окремо, дедлайн — «5:00 пп».
    func testPendingPartInOuncesAndTwelveHours() {
        let part = WidgetPresenter.part(day(13, 25, usSnapshot()), xp: 10)
        XCTAssertEqual(part.kind, .pending)
        XCTAssertEqual(part.unit, "унц.")
        XCTAssertEqual(part.headline, "ще до 5:00 пп")
        XCTAssertEqual(part.footnote, "3 год 35 хв", "тривалість не залежить від формату")
        let night = WidgetPresenter.part(day(7, 0, usSnapshot()), xp: 10)
        XCTAssertEqual(night.value, "8:00 дп")
    }

    func testInlineAndBlocks() throws {
        let us = day(13, 25, usSnapshot())
        XCTAssertTrue(WidgetPresenter.inline(us).hasPrefix("💧 "), WidgetPresenter.inline(us))
        XCTAssertTrue(WidgetPresenter.inline(us).contains(" з 68 унц. · ще "), WidgetPresenter.inline(us))
        let block = try XCTUnwrap(us.blocks.first)
        XCTAssertEqual(WidgetPresenter.blockHours(block, format: us.timeFormat), "8 дп–12 пп")
        XCTAssertEqual(WidgetPresenter.blockHours(block), "08–12")
        XCTAssertEqual(WidgetPresenter.blockValue(block, rhythm: true, unit: .usFluidOunces),
                       "\(VolumeUnit.usFluidOunces.units(block.drunkMl)) / 23")
    }

    func testReserveClockInTwelveHours() {
        let reserve = HydrationReserve.make(portions: Fixture.aheadPortions, capacityMl: 500, now: Fixture.date(13, 25),
                                            plannedReminder: nil, previous: nil, zero: Fixture.paceZero())
        let snapshot = usSnapshot(Fixture.snapshot(reserve: reserve))
        XCTAssertEqual(WidgetPresenter.reserve(day(13, 25, snapshot)).headline, "Пий о 3:24 пп")
        XCTAssertEqual(WidgetPresenter.reserve(day(7, 0, snapshot)).footnote, "запас рахую з 8:00 дп")
    }

    /// Знімок старішої збірки формату годинника не має — віджет показує 24 години, а не «відкрий застосунок».
    func testOldSnapshotWithoutTimeFormatDecodes() throws {
        let data = try JSONEncoder().encode(usSnapshot())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "timeFormatRaw")
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.timeFormat, .hours24)
        XCTAssertEqual(old.volumeUnit, .usFluidOunces)
    }

    /// Зміна формату — інший зміст: застосунок перезавантажує таймлайни, а не вважає знімок тим самим.
    func testFormatChangeIsNewContent() {
        var changed = Fixture.snapshot()
        changed.timeFormatRaw = TimeFormat.hours12.rawValue
        XCTAssertNotEqual(changed, Fixture.snapshot())
    }
}
