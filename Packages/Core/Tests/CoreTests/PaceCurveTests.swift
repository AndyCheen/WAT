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
        XCTAssertEqual(e(9).rounded(), 130)
        XCTAssertEqual(e(10).rounded(), 303)
        XCTAssertEqual(e(12).rounded(), 649)
        XCTAssertEqual(e(14).rounded(), 961)
        XCTAssertEqual(e(17).rounded(), 1429)
        XCTAssertEqual(e(20).rounded(), 1771)
        XCTAssertEqual(e(22), 2000, accuracy: 1e-9)
    }

    /// Час на одну склянку 250 мл — природний інтервал між порціями (87–132 хв).
    func testMinutesPerGlassMatchSpec() {
        func minutesPerGlass(in part: DayPart) -> Double {
            let segment = curve.segments.first { $0.part == part }!
            let rate = segment.ml / Double(segment.toMinute - segment.fromMinute)
            return 250 / rate
        }
        XCTAssertEqual(minutesPerGlass(in: .noon).rounded(.up), 87)
        XCTAssertEqual(minutesPerGlass(in: .afternoon).rounded(.up), 97)
        XCTAssertEqual(minutesPerGlass(in: .evening).rounded(.up), 132)
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

    /// E(14:15) = 1000 рівно в раціональних числах — похибка `Double` не має зсувати хвилину.
    func testExactBoundaryIsNotPushedByRoundingError() {
        let minute = try! XCTUnwrap(curve.minute(reaching: 1000))
        XCTAssertEqual(minute.rounded(.up), 14 * 60 + 15)
    }

    func testTargetOfAPart() {
        XCTAssertEqual(curve.target(fromMinute: 8 * 60, toMinute: 12 * 60).rounded(), 649)
        XCTAssertEqual(curve.target(fromMinute: 12 * 60, toMinute: 17 * 60).rounded(), 779)
    }
}
