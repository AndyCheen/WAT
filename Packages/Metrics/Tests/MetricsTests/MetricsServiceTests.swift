import XCTest
import SwiftData
import Core
import Persistence
@testable import Metrics

@MainActor
final class MetricsServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: MetricsService!
    private var store: MetricStore!
    private var clock: FixedClock!
    private var calendar: CalendarService!

    override func setUp() async throws {
        try await super.setUp()
        container = Database.makeInMemoryContainer()
        store = MetricStore(context: container.mainContext)
        clock = FixedClock(now: Self.date(day: 18, hour: 14))
        calendar = CalendarService(clock: clock)
        service = MetricsService(store: store, calendar: calendar)
    }

    private static func date(day: Int, hour: Int, month: Int = 7) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = month; c.day = day; c.hour = hour; c.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    func testRecordUpdatesAllPeriodCounters() {
        service.record(MetricEvent(name: .intakeAdded, value: 300, occurredAt: clock.now))

        XCTAssertEqual(service.sum(.intakeAdded, periodType: .day, periodKey: "2026-07-18"), 300)
        XCTAssertEqual(service.sum(.intakeAdded, periodType: .week, periodKey: "2026-W29"), 300)
        XCTAssertEqual(service.sum(.intakeAdded, periodType: .month, periodKey: "2026-07"), 300)
        XCTAssertEqual(service.sum(.intakeAdded, periodType: .year, periodKey: "2026"), 300)
        XCTAssertEqual(service.sumAllTime(.intakeAdded), 300)
    }

    func testDuplicateSourceRefIsIgnored() {
        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 200, occurredAt: clock.now, sourceRef: ref))
        let second = service.record(MetricEvent(name: .intakeAdded, value: 200, occurredAt: clock.now, sourceRef: ref))

        XCTAssertNil(second, "повторна подія з тим самим sourceRef не має зараховуватись")
        XCTAssertEqual(service.sumToday(.intakeAdded), 200)
    }

    func testDifferentMetricsWithSameSourceRefAreBothRecorded() {
        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 200, occurredAt: clock.now, sourceRef: ref))
        service.record(MetricEvent(name: .intakeCount, value: 1, occurredAt: clock.now, sourceRef: ref))

        XCTAssertEqual(service.sumToday(.intakeAdded), 200)
        XCTAssertEqual(service.sumToday(.intakeCount), 1)
    }

    func testRevertRollsBackEveryPeriod() {
        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 500, occurredAt: clock.now, sourceRef: ref))
        service.record(MetricEvent(name: .intakeCount, value: 1, occurredAt: clock.now, sourceRef: ref))
        service.record(MetricEvent(name: .intakeAdded, value: 200, occurredAt: clock.now, sourceRef: UUID()))

        let reverted = service.revert(sourceRef: ref, at: clock.now)

        XCTAssertEqual(reverted.count, 2)
        XCTAssertEqual(service.sumToday(.intakeAdded), 200, "лишається лише інша порція")
        XCTAssertEqual(service.sumToday(.intakeCount), 0)
        XCTAssertEqual(service.sumAllTime(.intakeAdded), 200)
    }

    func testRevertIsIdempotent() {
        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 500, occurredAt: clock.now, sourceRef: ref))
        service.revert(sourceRef: ref, at: clock.now)
        let second = service.revert(sourceRef: ref, at: clock.now)

        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(service.sumToday(.intakeAdded), 0)
    }

    func testRecordAfterRevertIsAllowedAgain() {
        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 300, occurredAt: clock.now, sourceRef: ref))
        service.revert(sourceRef: ref, at: clock.now)
        let again = service.record(MetricEvent(name: .intakeAdded, value: 300, occurredAt: clock.now, sourceRef: ref))

        XCTAssertNotNil(again, "після відкату ту саму дію можна повторити")
        XCTAssertEqual(service.sumToday(.intakeAdded), 300)
    }

    func testRebuildCountersReproducesSameState() {
        service.record(MetricEvent(name: .intakeAdded, value: 300, occurredAt: Self.date(day: 17, hour: 9)))
        service.record(MetricEvent(name: .intakeAdded, value: 500, occurredAt: Self.date(day: 18, hour: 10)))
        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 250, occurredAt: clock.now, sourceRef: ref))
        service.revert(sourceRef: ref, at: clock.now)

        let before = (
            day17: service.sum(.intakeAdded, periodType: .day, periodKey: "2026-07-17"),
            day18: service.sum(.intakeAdded, periodType: .day, periodKey: "2026-07-18"),
            all: service.sumAllTime(.intakeAdded)
        )

        service.rebuildCounters()

        XCTAssertEqual(service.sum(.intakeAdded, periodType: .day, periodKey: "2026-07-17"), before.day17)
        XCTAssertEqual(service.sum(.intakeAdded, periodType: .day, periodKey: "2026-07-18"), before.day18)
        XCTAssertEqual(service.sumAllTime(.intakeAdded), before.all)
        XCTAssertEqual(service.sumAllTime(.intakeAdded), 800, "відкочена подія не повертається")
    }

    func testEventsCarryHourBucketForHeatmap() {
        service.record(MetricEvent(name: .intakeAdded, value: 200, occurredAt: Self.date(day: 18, hour: 7)))
        service.record(MetricEvent(name: .intakeAdded, value: 200, occurredAt: Self.date(day: 18, hour: 21)))

        let hours = service.events(.intakeAdded, day: DayKey(rawValue: "2026-07-18")).map(\.hourBucket)
        XCTAssertEqual(hours.sorted(), [7, 21])
    }

    func testSubscriberReceivesRecordAndRevert() {
        final class Spy: MetricsSubscriber {
            var recorded: [RecordedMetricEvent] = []
            var reverted: [UUID] = []
            func metricsDidRecord(_ event: RecordedMetricEvent, service: MetricsService) { recorded.append(event) }
            func metricsDidRevert(_ events: [RecordedMetricEvent], sourceRef: UUID, service: MetricsService) {
                reverted.append(sourceRef)
            }
        }
        let spy = Spy()
        service.subscribe(spy)

        let ref = UUID()
        service.record(MetricEvent(name: .intakeAdded, value: 100, occurredAt: clock.now, sourceRef: ref))
        service.revert(sourceRef: ref, at: clock.now)

        XCTAssertEqual(spy.recorded.count, 1)
        XCTAssertEqual(spy.recorded.first?.name, .intakeAdded)
        XCTAssertEqual(spy.reverted, [ref])
    }
}
