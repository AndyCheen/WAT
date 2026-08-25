import XCTest
import Persistence
@testable import Hydration

final class GoalFormulaTests: XCTestCase {
    func testSpecFormulaUsesGenderAndAge() {
        let formula = SpecGoalFormula()
        // 70 кг × 35 мл × 1.0 + 350 = 2800 → округлення до 50
        let male = formula.dailyGoalMl(
            for: GoalInputs(weightKg: 70, gender: .male, birthYear: 2000, activity: .medium),
            currentYear: 2026
        )
        XCTAssertEqual(male, 2800)

        // 70 кг × 30 мл × 1.0 + 350 = 2450
        let female = formula.dailyGoalMl(
            for: GoalInputs(weightKg: 70, gender: .female, birthYear: 2000, activity: .medium),
            currentYear: 2026
        )
        XCTAssertEqual(female, 2450)
    }

    func testSpecFormulaAgeCoefficient() {
        let formula = SpecGoalFormula()
        let young = formula.dailyGoalMl(
            for: GoalInputs(weightKg: 80, gender: .male, birthYear: 2000, activity: .low), currentYear: 2026
        )
        let senior = formula.dailyGoalMl(
            for: GoalInputs(weightKg: 80, gender: .male, birthYear: 1960, activity: .low), currentYear: 2026
        )
        XCTAssertGreaterThan(young, senior, "з віком коефіцієнт знижується")
    }

    func testMockupFormulaMatchesArtboard4a() {
        // computeGoalMl з макета: 70×30 + 350(середня) + 0 = 2450 → 2450
        let formula = MockupGoalFormula()
        XCTAssertEqual(
            formula.dailyGoalMl(for: GoalInputs(weightKg: 70, activity: .medium), currentYear: 2026),
            2450
        )
        // 70×30 + 700(висока) + 400(спека) = 3200
        XCTAssertEqual(
            formula.dailyGoalMl(for: GoalInputs(weightKg: 70, activity: .high, climate: .hot), currentYear: 2026),
            3200
        )
    }

    func testResultIsAlwaysRoundedAndClamped() {
        let formula = SpecGoalFormula()
        for weight in stride(from: 35.0, through: 160.0, by: 0.5) {
            let goal = formula.dailyGoalMl(for: GoalInputs(weightKg: weight, gender: .male), currentYear: 2026)
            XCTAssertEqual(goal % 50, 0, "норма кратна 50 мл")
            XCTAssertGreaterThanOrEqual(goal, 500)
            XCTAssertLessThanOrEqual(goal, 5000)
        }
    }
}
