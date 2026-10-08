import XCTest
import Core
@testable import Widgets

/// «Запас води» (SPEC-WIDGETS §5): стрибок на об'єм порції, рівний спад до нуля за 10 хв до нагадування.
final class HydrationReserveTests: XCTestCase {
    private let capacity = HydrationReserve.capacity(typicalPortionMl: 250)

    func testCapacityIsTwoTypicalPortions() {
        XCTAssertEqual(capacity, 500)
    }

    func testNoPortionsMeansEmptyReserve() {
        let reserve = HydrationReserve.make(portions: [], capacityMl: capacity, now: Fixture.date(9, 0),
                                            plannedReminder: nil, previous: nil, zero: Fixture.paceZero())
        XCTAssertNil(reserve)
    }

    /// Одна склянка — пів краплі; нуль за 10 хв до нагадування з плану, а не за темпом.
    func testPortionJumpsAndDecaysToTenMinutesBeforePlannedReminder() throws {
        let portion = Fixture.portion(9, 0, 250, id: 1)
        let planned = Fixture.date(10, 40)
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: [portion], capacityMl: capacity, now: Fixture.date(9, 0), plannedReminder: planned,
            previous: nil, zero: Fixture.paceZero()))

        XCTAssertEqual(reserve.anchorMl, 250)
        XCTAssertEqual(reserve.fraction(at: Fixture.date(9, 0)), 0.5, accuracy: 0.001)
        XCTAssertEqual(reserve.zeroAt, Fixture.date(10, 30))
        XCTAssertEqual(reserve.reminderAt, planned)
        XCTAssertEqual(reserve.level(at: Fixture.date(9, 45)), 125, accuracy: 0.01)
        XCTAssertTrue(reserve.isEmpty(at: Fixture.date(10, 30)))
        XCTAssertFalse(reserve.isEmpty(at: Fixture.date(10, 29)))
    }

    /// Без нагадувань у плані — нуль за кривою темпу: та сама формула, що в планувальника.
    func testWithoutPlanZeroFollowsPace() throws {
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: Fixture.aheadPortions, capacityMl: capacity, now: Fixture.date(13, 25), plannedReminder: nil,
            previous: nil, zero: Fixture.paceZero()))
        // 1000 мл о 12:50: E(t) = 1250 о 15:23:49 → нагадування 15:24, нуль 15:14 (як у макеті).
        XCTAssertEqual(reserve.reminderAt, Fixture.date(15, 24))
        XCTAssertEqual(reserve.zeroAt, Fixture.date(15, 14))
        XCTAssertEqual(reserve.mode, .flowing)
    }

    /// Друга порція додається до того, що лишилось, — не до повної краплі.
    func testSecondPortionAddsToWhatIsLeft() throws {
        let first = Fixture.portion(9, 0, 250, id: 1)
        let zero = Fixture.paceZero()
        let firstZero = zero(first.at, 250).at
        let midway = first.at.addingTimeInterval(firstZero.timeIntervalSince(first.at) / 2)
        let second = WidgetSnapshot.Portion(id: Fixture.uuid(2), at: midway, ml: 100)
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: [first, second], capacityMl: capacity, now: midway, plannedReminder: nil, previous: nil, zero: zero))
        XCTAssertEqual(reserve.anchorMl, 225, accuracy: 0.01)
    }

    func testLevelIsCappedByCapacity() throws {
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: [Fixture.portion(9, 0, 750, id: 1)], capacityMl: capacity, now: Fixture.date(9, 0),
            plannedReminder: nil, previous: nil, zero: Fixture.paceZero()))
        XCTAssertEqual(reserve.anchorMl, 500)
        XCTAssertEqual(reserve.fraction(at: Fixture.date(9, 0)), 1)
    }

    /// Undo — просто програвання без прибраної порції.
    func testUndoReplaysWithoutRemovedPortion() throws {
        let all = Fixture.aheadPortions
        let before = try XCTUnwrap(HydrationReserve.make(
            portions: Array(all.dropLast()), capacityMl: capacity, now: Fixture.date(12, 50), plannedReminder: nil,
            previous: nil, zero: Fixture.paceZero()))
        let after = try XCTUnwrap(HydrationReserve.make(
            portions: all, capacityMl: capacity, now: Fixture.date(12, 50), plannedReminder: nil, previous: nil,
            zero: Fixture.paceZero()))
        let undone = try XCTUnwrap(HydrationReserve.make(
            portions: Array(all.dropLast()), capacityMl: capacity, now: Fixture.date(12, 51), plannedReminder: nil,
            previous: after, zero: Fixture.paceZero()))
        XCTAssertEqual(undone, before)
    }

    func testGoalMetDecaysToBedtime() throws {
        let portions = [Fixture.portion(9, 0, 1000, id: 1), Fixture.portion(14, 0, 1000, id: 2)]
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: portions, capacityMl: capacity, now: Fixture.date(14, 0), plannedReminder: nil, previous: nil,
            zero: Fixture.paceZero()))
        XCTAssertEqual(reserve.mode, .goalMet)
        XCTAssertEqual(reserve.zeroAt, Fixture.date(22, 0))
        XCTAssertNil(reserve.reminderAt)
    }

    /// Та сама остання порція, нагадування відсунулось (відкриття застосунку, §6.2): рівень «зараз» не
    /// стрибає — змінюється лише нахил.
    func testSameAnchorKeepsLevelAndChangesSlope() throws {
        let portion = Fixture.portion(9, 0, 250, id: 1)
        let first = try XCTUnwrap(HydrationReserve.make(
            portions: [portion], capacityMl: capacity, now: Fixture.date(9, 0), plannedReminder: Fixture.date(10, 40),
            previous: nil, zero: Fixture.paceZero()))
        let now = Fixture.date(9, 45)
        let moved = try XCTUnwrap(HydrationReserve.make(
            portions: [portion], capacityMl: capacity, now: now, plannedReminder: Fixture.date(11, 10),
            previous: first, zero: Fixture.paceZero()))

        XCTAssertEqual(moved.level(at: now), first.level(at: now), accuracy: 0.01)
        XCTAssertEqual(moved.zeroAt, Fixture.date(11, 0))
        XCTAssertEqual(moved.anchorAt, now)
    }

    /// Порожня крапля лишається порожньою: нагадування вже прийшло, наступне в плані — повторне.
    func testEmptyReserveStaysEmptyForSameAnchor() throws {
        let portion = Fixture.portion(9, 0, 250, id: 1)
        let first = try XCTUnwrap(HydrationReserve.make(
            portions: [portion], capacityMl: capacity, now: Fixture.date(9, 0), plannedReminder: Fixture.date(10, 40),
            previous: nil, zero: Fixture.paceZero()))
        let later = try XCTUnwrap(HydrationReserve.make(
            portions: [portion], capacityMl: capacity, now: Fixture.date(10, 50), plannedReminder: Fixture.date(11, 10),
            previous: first, zero: Fixture.paceZero()))
        XCTAssertEqual(later, first)
        XCTAssertTrue(later.isEmpty(at: Fixture.date(10, 50)))
    }

    /// Системний прогрес-бар на екрані блокування: у момент порції частка інтервалу = L₀ / C.
    func testTimerStartMatchesLevelAtAnchor() throws {
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: [Fixture.portion(9, 0, 250, id: 1)], capacityMl: capacity, now: Fixture.date(9, 0),
            plannedReminder: Fixture.date(10, 40), previous: nil, zero: Fixture.paceZero()))
        let span = reserve.zeroAt.timeIntervalSince(reserve.timerStart)
        let leftAtAnchor = reserve.zeroAt.timeIntervalSince(reserve.anchorAt) / span
        XCTAssertEqual(leftAtAnchor, 0.5, accuracy: 0.001)
        let mid = Fixture.date(9, 45)
        XCTAssertEqual(reserve.zeroAt.timeIntervalSince(mid) / span, reserve.fraction(at: mid), accuracy: 0.001)
    }

    /// Чекпоінт одразу після порції не «спалює» краплю на очах — спад не коротший за 15 хв.
    func testMinimumSpan() throws {
        let reserve = try XCTUnwrap(HydrationReserve.make(
            portions: [Fixture.portion(9, 0, 250, id: 1)], capacityMl: capacity, now: Fixture.date(9, 0),
            plannedReminder: Fixture.date(9, 5), previous: nil, zero: Fixture.paceZero()))
        XCTAssertEqual(reserve.zeroAt, Fixture.date(9, 15))
    }
}
