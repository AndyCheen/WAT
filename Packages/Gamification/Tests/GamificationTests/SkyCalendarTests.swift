import XCTest
@testable import Gamification

/// Сонцестояння й повня проти довідкових моментів (UTC) — допуск дві хвилини.
final class SkyCalendarTests: XCTestCase {
    private let iso = ISO8601DateFormatter()

    private func assertClose(_ date: Date, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let reference = iso.date(from: expected)!
        XCTAssertLessThan(abs(date.timeIntervalSince(reference)), 120, "\(iso.string(from: date)) ≠ \(expected)",
                          file: file, line: line)
    }

    func testSolstices() {
        assertClose(SkyCalendar.solstice(.june, year: 2024), "2024-06-20T20:51:00Z")
        assertClose(SkyCalendar.solstice(.december, year: 2024), "2024-12-21T09:20:00Z")
        assertClose(SkyCalendar.solstice(.june, year: 2025), "2025-06-21T02:42:00Z")
        assertClose(SkyCalendar.solstice(.december, year: 2025), "2025-12-21T15:03:00Z")
        assertClose(SkyCalendar.solstice(.june, year: 2026), "2026-06-21T08:24:00Z")
        assertClose(SkyCalendar.solstice(.december, year: 2026), "2026-12-21T20:50:00Z")
    }

    func testFullMoonsOf2026() {
        let moons = SkyCalendar.fullMoons(from: iso.date(from: "2026-01-01T00:00:00Z")!,
                                          to: iso.date(from: "2026-12-31T23:59:59Z")!)
        let expected = [
            "2026-01-03T10:03:00Z", "2026-02-01T22:09:00Z", "2026-03-03T11:38:00Z", "2026-04-02T02:12:00Z",
            "2026-05-01T17:23:00Z", "2026-05-31T08:45:00Z", "2026-06-29T23:57:00Z", "2026-07-29T14:36:00Z",
            "2026-08-28T04:18:00Z", "2026-09-26T16:49:00Z", "2026-10-26T04:12:00Z", "2026-11-24T14:53:00Z",
            "2026-12-24T01:28:00Z"
        ]
        XCTAssertEqual(moons.count, expected.count)
        for (moon, reference) in zip(moons, expected) { assertClose(moon, reference) }
    }
}
