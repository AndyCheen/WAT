import XCTest
import Core
@testable import Insights

final class InsightsCalculatorsTests: XCTestCase {

    // MARK: - Бал рівномірності

    func testPerfectDistributionScores100() {
        // Розподіл точно за ідеальними частками (20/20/30/22/8 від 2000 мл)
        let totals = DayPart.allCases.map { Int(2000 * $0.idealShare) }
        XCTAssertEqual(InsightsCalculators.evennessScore(partTotals: totals), 100)
    }

    func testEmptyDayScoresZero() {
        XCTAssertEqual(InsightsCalculators.evennessScore(partTotals: [0, 0, 0, 0, 0]), 0)
    }

    func testAllWaterInOneNightPartScoresLow() {
        let score = InsightsCalculators.evennessScore(partTotals: [0, 0, 0, 0, 2000])
        XCTAssertLessThan(score, 15, "уся вода вночі — найгірший розподіл")
    }

    func testScoreIsAlwaysInRange() {
        let samples: [[Int]] = [
            [0, 250, 1200, 900, 150], [2000, 0, 0, 0, 0], [400, 400, 400, 400, 400],
            [100, 0, 50, 0, 0], [0, 0, 3000, 0, 0]
        ]
        for totals in samples {
            let score = InsightsCalculators.evennessScore(partTotals: totals)
            XCTAssertTrue((0...100).contains(score), "\(totals) → \(score)")
        }
    }

    func testEvennessRowsAreScaledToCommonMaximum() {
        let rows = InsightsCalculators.evennessRows(partTotals: [0, 250, 1200, 900, 150], goalMl: 2000)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].ml, 0)
        XCTAssertEqual(rows[2].fraction, 1.0, accuracy: 0.001, "найбільша смуга займає всю ширину")
        XCTAssertTrue(rows.allSatisfy { $0.fraction <= 1 && $0.tickFraction <= 1 })
        XCTAssertEqual(rows[2].idealMl, 600, "ідеал для «Дня» — 30 % від 2000 мл")
    }

    // MARK: - Типова доба

    func testTypicalDayMedianOfIdenticalDays() {
        let day = [200, 300, 500, 400, 0]
        let report = InsightsCalculators.typicalDay(dailyPartTotals: Array(repeating: day, count: 5))

        XCTAssertEqual(report.daysCounted, 5)
        XCTAssertEqual(report.rows[2].median, 500.0 / 1400.0, accuracy: 0.001)
        XCTAssertEqual(report.rows[2].low, report.rows[2].high, accuracy: 0.001, "однакові дні — нульовий розкид")
    }

    func testTypicalDaySpreadWidensWithVariety() {
        let days = [
            [1000, 0, 0, 0, 0], [0, 0, 1000, 0, 0], [500, 0, 500, 0, 0],
            [0, 500, 500, 0, 0], [250, 250, 500, 0, 0]
        ]
        let report = InsightsCalculators.typicalDay(dailyPartTotals: days)
        XCTAssertGreaterThan(report.rows[0].high - report.rows[0].low, 0.1)
    }

    func testEmptyDaysAreIgnored() {
        let report = InsightsCalculators.typicalDay(
            dailyPartTotals: [[0, 0, 0, 0, 0], [200, 300, 500, 0, 0], [0, 0, 0, 0, 0]]
        )
        XCTAssertEqual(report.daysCounted, 1, "дні без води не спотворюють медіану")
    }

    func testNoDataGivesEmptyReport() {
        XCTAssertEqual(InsightsCalculators.typicalDay(dailyPartTotals: []), .empty)
        XCTAssertEqual(InsightsCalculators.typicalDay(dailyPartTotals: [[0, 0, 0, 0, 0]]), .empty)
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
