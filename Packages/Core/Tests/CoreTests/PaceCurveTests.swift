import XCTest
@testable import Core

/// Крива темпу — SPEC-NOTIFICATIONS §4. Від неї рахуються нагадування, вечірній підсумок
/// і (етап B) чекпоінти, тож таблиця з ТЗ прибита дослівно.
final class PaceCurveTests: XCTestCase {
    private let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    private func e(_ hour: Int, _ minute: Int = 0) -> Double {
        curve.expected(atMinute: Double(hour * 60 + minute))
    }

    func testMatchesSpecTable() {
        XCTAssertEqual(e(9).rounded(), 138)
        XCTAssertEqual(e(10).rounded(), 321)
        XCTAssertEqual(e(12).rounded(), 689)
        XCTAssertEqual(e(14).rounded(), 1019)
        XCTAssertEqual(e(17).rounded(), 1515)
        XCTAssertEqual(e(20).rounded(), 1879)
        XCTAssertEqual(e(22), 2000, accuracy: 1e-9)
    }

    /// Час на одну склянку 250 мл — природний інтервал між порціями (82–124 хв), а у
    /// вікні спаду перед сном — удвічі довший.
    func testMinutesPerGlassMatchSpec() {
        func minutesPerGlass(from: Int, to: Int) -> Double {
            let rate = (e(to) - e(from)) / Double((to - from) * 60)
            return 250 / rate
        }
        XCTAssertEqual(minutesPerGlass(from: 9, to: 12).rounded(.up), 82)
        XCTAssertEqual(minutesPerGlass(from: 12, to: 17).rounded(.up), 91)
        XCTAssertEqual(minutesPerGlass(from: 17, to: 20).rounded(.up), 124)
        XCTAssertEqual(minutesPerGlass(from: 20, to: 22).rounded(.up), 248)
    }

    /// Спад (WAT-43, §29): останні 2 год до відбою — рівно половина темпу кінця вечора.
    func testTaperHalvesThePaceInTheLastTwoHours() {
        let before = e(19, 59) - e(19, 58)
        let inside = e(20, 1) - e(20, 0)
        XCTAssertEqual(inside, before * PaceCurve.taperFactor, accuracy: 1e-9)
        XCTAssertEqual((e(22) - e(20)).rounded(), 121, "було 229 мл без спаду")
    }

    /// Вікно спаду рахується від відбою людини: при 07:00–23:00 воно 21–23 і перетинає межу
    /// вечора й ночі, а вечір до 21:00 іде звичайним темпом.
    func testTaperFollowsBedtimeAcrossPartBoundary() {
        let late = PaceCurve(goalMl: 2000, wakeMinutes: 7 * 60, sleepMinutes: 23 * 60)
        func rate(_ minute: Int) -> Double {
            late.expected(atMinute: Double(minute + 1)) - late.expected(atMinute: Double(minute))
        }
        XCTAssertEqual(rate(21 * 60), rate(20 * 60) * PaceCurve.taperFactor, accuracy: 1e-9, "вечір у вікні")
        XCTAssertEqual(rate(22 * 60 + 30), rate(21 * 60) * (0.08 / 7) / (0.22 / 5), accuracy: 1e-9,
                       "ніч у вікні — теж половина свого темпу")
        XCTAssertEqual(late.expected(atMinute: 23 * 60), 2000, accuracy: 1e-9)
    }

    /// Спад не ділить частину доби: інакше вечір 20–22 став би окремою ціллю й чекпоінтом «до 20:00».
    func testTaperDoesNotSplitSegmentsOrGoalBlocks() {
        XCTAssertEqual(curve.segments.map(\.part), [.morning, .noon, .afternoon, .evening])
        XCTAssertEqual(curve.segments.reduce(0) { $0 + $1.ml }, 2000, accuracy: 1e-9)
        XCTAssertEqual(curve.goalBlocks().map(\.toMinute), [12 * 60, 17 * 60, 22 * 60])
    }

    func testZeroBeforeWakeAndFullAfterSleep() {
        XCTAssertEqual(e(7), 0)
        XCTAssertEqual(e(8), 0)
        XCTAssertEqual(e(23), 2000)
    }

    func testIsMonotonic() {
        var previous = -1.0
        for minute in stride(from: 0, through: 24 * 60, by: 5) {
            let value = curve.expected(atMinute: Double(minute))
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    /// 07:00–23:00 зачіпає ніч з обох боків доби — вона дає свою частку, а не зникає.
    func testNightPiecesCountWhenInsideActiveHours() {
        let late = PaceCurve(goalMl: 2000, wakeMinutes: 7 * 60, sleepMinutes: 23 * 60)
        let night = late.segments.filter { $0.part == .night }
        XCTAssertEqual(night.count, 1, "22–23 — шматок ночі; 05–07 до підйому не входить")
        XCTAssertEqual(late.segments.reduce(0) { $0 + $1.ml }, 2000, accuracy: 1e-9)
    }

    /// Обернена функція — нагадування шукає момент, коли темп «наздогнав» порцію.
    func testMinuteReachingIsInverse() {
        let minute = try! XCTUnwrap(curve.minute(reaching: 500))
        XCTAssertEqual(curve.expected(atMinute: minute), 500, accuracy: 1e-6)
        XCTAssertEqual(curve.minute(reaching: 0), 480)
        XCTAssertNil(curve.minute(reaching: 2001))
    }

    /// E(13:53) = 1000 рівно в раціональних числах — похибка `Double` не має зсувати хвилину.
    func testExactBoundaryIsNotPushedByRoundingError() {
        let minute = try! XCTUnwrap(curve.minute(reaching: 1000))
        XCTAssertEqual(minute.rounded(.up), 13 * 60 + 53)
    }

    func testTargetOfAPart() {
        XCTAssertEqual(curve.target(fromMinute: 8 * 60, toMinute: 12 * 60).rounded(), 689)
        XCTAssertEqual(curve.target(fromMinute: 12 * 60, toMinute: 17 * 60).rounded(), 826)
    }

    // MARK: - Наступна порція за темпом (§6.2, WAT-30)

    /// Від підйому без порцій: E(t) = 250 о ~09:37 — пізніше за мінімальний інтервал (09:00).
    func testNextDueReachesTypicalPortionFromWake() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 480, sleepMinutes: 1320)
        let due = curve.nextDueMinute(anchorMinute: 480, drunkMl: 0, portionMl: 250, k: 1, minGapMinutes: 60, maxGapMinutes: 180)
        XCTAssertEqual(due, 576.7, accuracy: 0.1)
    }

    /// Хто випередив темп, отримує нагадування не пізніше `maxGap`; хто щойно випив — не раніше `minGap`.
    func testNextDueIsClampedByGaps() {
        let curve = PaceCurve(goalMl: 2000, wakeMinutes: 480, sleepMinutes: 1320)
        let ahead = curve.nextDueMinute(anchorMinute: 600, drunkMl: 1500, portionMl: 250, k: 1, minGapMinutes: 60, maxGapMinutes: 180)
        XCTAssertEqual(ahead, 780)
        // Мала порція: темп наздоганяє її за ~18 хв, але раніше ніж за годину не нагадуємо.
        let small = curve.nextDueMinute(anchorMinute: 760, drunkMl: 0, portionMl: 50, k: 1, minGapMinutes: 60, maxGapMinutes: 180)
        XCTAssertEqual(small, 820)
    }
}
