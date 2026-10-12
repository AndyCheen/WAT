import XCTest
@testable import Widgets

final class WidgetStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTrip() throws {
        let store = WidgetSnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
        let reserve = HydrationReserve.make(portions: Fixture.aheadPortions, capacityMl: 500, now: Fixture.date(13, 25),
                                            plannedReminder: Fixture.date(15, 0), previous: nil, zero: Fixture.paceZero())
        let snapshot = Fixture.snapshot(
            reserve: reserve, lastAction: .init(intakeId: Fixture.uuid(4), ml: 200, at: Fixture.date(12, 50)))
        XCTAssertTrue(store.write(snapshot))
        XCTAssertEqual(store.read(), snapshot)
    }

    func testMissingFileOrGroup() {
        XCTAssertNil(WidgetSnapshotStore(url: directory.appendingPathComponent("none.json")).read())
        XCTAssertNil(WidgetSnapshotStore(url: nil).read())
        XCTAssertFalse(WidgetSnapshotStore(url: nil).write(Fixture.snapshot()))
    }

    /// Старий формат віджет не читає — показує «Відкрий застосунок», а не бите.
    func testOtherVersionIsIgnored() throws {
        let store = WidgetSnapshotStore(url: directory.appendingPathComponent("snapshot.json"))
        var snapshot = Fixture.snapshot()
        snapshot.version = WidgetSnapshot.currentVersion + 1
        XCTAssertTrue(store.write(snapshot))
        XCTAssertNil(store.read())
    }

    func testSameContentIgnoresGenerationTime() {
        let a = Fixture.snapshot()
        var b = a
        b.generatedAt = Fixture.date(14, 0)
        XCTAssertTrue(a.sameContent(as: b))
        b.totalMl += 50
        XCTAssertFalse(a.sameContent(as: b))
    }

    /// «Дві кнопки» типово — склянка й перша інша кнопка головного, а не дві однакові.
    func testPairSecondButton() {
        var snapshot = Fixture.snapshot()
        XCTAssertEqual(snapshot.pairSecondHomeIndex, 1, "склянка 250 — тоді 500, а не 200")
        snapshot.homeButtons = [150, 200, 250]
        XCTAssertEqual(snapshot.pairSecondHomeIndex, 0, "більшої немає — перша інша")
        snapshot.homeButtons = [250]
        XCTAssertNil(snapshot.pairSecondHomeIndex)
    }

    func testLinkRoundTrip() {
        for link in WidgetLink.allCases {
            XCTAssertEqual(WidgetLink(url: link.url), link)
        }
        XCTAssertEqual(WidgetLink.custom.url.absoluteString, "watertracker://custom")
        XCTAssertNil(WidgetLink(url: URL(string: "https://custom")!))
        XCTAssertNil(WidgetLink(url: URL(string: "watertracker://unknown")!))
    }
}
