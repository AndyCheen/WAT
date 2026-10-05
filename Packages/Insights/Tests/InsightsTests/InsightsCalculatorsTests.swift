import XCTest
import Core
@testable import Insights

final class InsightsCalculatorsTests: XCTestCase {

    // MARK: - Бал рівномірності

    /// Крива 08:00–22:00, норма 2000: цілі 130 / 519 / 780 / 571 / 0.
    private let curve = PaceCurve(goalMl: 2000, wakeMinutes: 8 * 60, sleepMinutes: 22 * 60)

    func testDistributionAlongCurveScores100() {
        XCTAssertEqual(InsightsCalculators.evennessScore(partTotals: curve.partTargetsMl(), shares: curve.partShares()), 100)
    }

    func testEmptyDayScoresZero() {
        XCTAssertEqual(InsightsCalculators.evennessScore(partTotals: [0, 0, 0, 0, 0], shares: curve.partShares()), 0)
    }

    /// Ніч поза активними годинами має частку 0: уся вода там — нульовий бал (§13.6).
    func testAllWaterAtNightScoresZero() {
        XCTAssertEqual(InsightsCalculators.evennessScore(partTotals: [0, 0, 0, 0, 2000], shares: curve.partShares()), 0)
    }

    /// Старі фіксовані 20 % ранку вже не ціль: при підйомі о 08:00 повна ранкова «норма» — перебір.
    func testOldFixedSharesNoLongerPerfect() {
        let old = DayPart.allCases.map { Int(2000 * $0.idealShare) }
        XCTAssertLessThan(InsightsCalculators.evennessScore(partTotals: old, shares: curve.partShares()), 90)
    }

    func testScoreIsAlwaysInRange() {
        let samples: [[Int]] = [
            [0, 250, 1200, 900, 150], [2000, 0, 0, 0, 0], [400, 400, 400, 400, 400],
            [100, 0, 50, 0, 0], [0, 0, 3000, 0, 0]
        ]
        for totals in samples {
            let score = InsightsCalculators.evennessScore(partTotals: totals, shares: curve.partShares())
            XCTAssertTrue((0...100).contains(score), "\(totals) → \(score)")
        }
    }

    func testEvennessRowsAreScaledToCommonMaximum() {
        let rows = InsightsCalculators.evennessRows(partTotals: [0, 250, 1200, 900, 150], targetsMl: curve.partTargetsMl())
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].ml, 0)
        XCTAssertEqual(rows[2].fraction, 1.0, accuracy: 0.001, "найбільша смуга займає всю ширину")
        XCTAssertTrue(rows.allSatisfy { $0.fraction <= 1 && ($0.tickFraction ?? 0) <= 1 })
        XCTAssertEqual(rows[2].idealMl, 780, "«День» — шматок кривої 12–17")
        XCTAssertNil(rows[4].tickFraction, "ніч — без ризки")
        XCTAssertEqual(rows[4].ml, 150, "випите вночі все одно показується")
    }

    // MARK: - Типова доба

    private func days(_ totals: [[Int]]) -> [InsightsCalculators.DayParts] {
        totals.map { InsightsCalculators.DayParts(partTotals: $0, shares: curve.partShares()) }
    }

    func testTypicalDayMedianOfIdenticalDays() {
        let day = [200, 300, 500, 400, 0]
        let report = InsightsCalculators.typicalDay(days: days(Array(repeating: day, count: 5)))

        XCTAssertEqual(report.daysCounted, 5)
        XCTAssertEqual(report.rows[2].median, 500.0 / 1400.0, accuracy: 0.001)
        XCTAssertEqual(report.rows[2].low, report.rows[2].high, accuracy: 0.001, "однакові дні — нульовий розкид")
        XCTAssertEqual(report.rows[2].ideal ?? 0, 0.39, accuracy: 0.001)
        XCTAssertNil(report.rows[4].ideal)
    }

    /// Різні розклади днів — ризка посередині: середня частка кривих.
    func testTypicalDayIdealAveragesSchedules() {
        let late = PaceCurve(goalMl: 2000, wakeMinutes: 10 * 60, sleepMinutes: 23 * 60)
        let input = [
            InsightsCalculators.DayParts(partTotals: [100, 500, 800, 600, 0], shares: curve.partShares()),
            InsightsCalculators.DayParts(partTotals: [0, 300, 900, 600, 200], shares: late.partShares())
        ]
        let report = InsightsCalculators.typicalDay(days: input)
        let expected = (curve.partShares()[4] + late.partShares()[4]) / 2
        XCTAssertEqual(report.rows[4].ideal ?? 0, expected, accuracy: 1e-9)
        XCTAssertGreaterThan(expected, 0, "відбій о 23:00 — година ночі з ціллю")
    }

    func testTypicalDaySpreadWidensWithVariety() {
        let report = InsightsCalculators.typicalDay(days: days([
            [1000, 0, 0, 0, 0], [0, 0, 1000, 0, 0], [500, 0, 500, 0, 0],
            [0, 500, 500, 0, 0], [250, 250, 500, 0, 0]
        ]))
        XCTAssertGreaterThan(report.rows[0].high - report.rows[0].low, 0.1)
    }

    func testEmptyDaysAreIgnored() {
        let report = InsightsCalculators.typicalDay(days: days([[0, 0, 0, 0, 0], [200, 300, 500, 0, 0], [0, 0, 0, 0, 0]]))
        XCTAssertEqual(report.daysCounted, 1, "дні без води не спотворюють медіану")
    }

    func testNoDataGivesEmptyReport() {
        XCTAssertEqual(InsightsCalculators.typicalDay(days: []), .empty)
        XCTAssertEqual(InsightsCalculators.typicalDay(days: days([[0, 0, 0, 0, 0]])), .empty)
    }

    func testPercentileInterpolates() {
        let values = [0.0, 0.25, 0.5, 0.75, 1.0]
        XCTAssertEqual(InsightsCalculators.percentile(values, 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(InsightsCalculators.percentile(values, 0.25), 0.25, accuracy: 0.0001)
        XCTAssertEqual(InsightsCalculators.percentile([], 0.5), 0)
        XCTAssertEqual(InsightsCalculators.percentile([0.42], 0.75), 0.42)
    }

    // MARK: - Теплокарта

    func testHeatmapBuckets() {
        XCTAssertNil(InsightsCalculators.bucketIndex(forHour: 3), "ніч поза сіткою 6…23")
        XCTAssertEqual(InsightsCalculators.bucketIndex(forHour: 6), 0)
        XCTAssertEqual(InsightsCalculators.bucketIndex(forHour: 7), 0, "бакет покриває дві години")
        XCTAssertEqual(InsightsCalculators.bucketIndex(forHour: 12), 3)
        XCTAssertEqual(InsightsCalculators.bucketIndex(forHour: 23), 8)
    }

    func testHeatmapLevels() {
        XCTAssertEqual(InsightsCalculators.heatmapLevel(ml: 0, maxMl: 1000), 0)
        XCTAssertEqual(InsightsCalculators.heatmapLevel(ml: 100, maxMl: 1000), 1)
        XCTAssertEqual(InsightsCalculators.heatmapLevel(ml: 400, maxMl: 1000), 2)
        XCTAssertEqual(InsightsCalculators.heatmapLevel(ml: 700, maxMl: 1000), 3)
        XCTAssertEqual(InsightsCalculators.heatmapLevel(ml: 1000, maxMl: 1000), 4)
        XCTAssertEqual(InsightsCalculators.heatmapLevel(ml: 100, maxMl: 0), 0, "без даних — нульовий рівень")
    }
}
