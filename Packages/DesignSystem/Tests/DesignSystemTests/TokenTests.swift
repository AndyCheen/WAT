import XCTest
import SwiftUI
@testable import DesignSystem

/// Захист від «дрейфу» палітри: значення звірені з DESIGN-TOKENS.md.
final class TokenTests: XCTestCase {

    private func components(_ color: Color) -> (r: Int, g: Int, b: Int, a: Double) {
        let resolved = color.resolve(in: EnvironmentValues())
        return (
            Int((Double(resolved.red) * 255).rounded()),
            Int((Double(resolved.green) * 255).rounded()),
            Int((Double(resolved.blue) * 255).rounded()),
            Double(resolved.opacity)
        )
    }

    func testHexParsing() {
        let parsed = components(Color(hex: "#5aa9f0"))
        XCTAssertEqual(parsed.r, 90)
        XCTAssertEqual(parsed.g, 169)
        XCTAssertEqual(parsed.b, 240)
        XCTAssertEqual(parsed.a, 1, accuracy: 0.01)
    }

    func testHexWithoutHashAndWithAlpha() {
        XCTAssertEqual(components(Color(hex: "5aa9f0")).r, 90)
        XCTAssertEqual(components(Color(hex: "#5aa9f080")).a, 0.5, accuracy: 0.01)
    }

    func testLightThemeMatchesMockup() {
        let accent = components(WTTheme.light.accent)
        XCTAssertEqual([accent.r, accent.g, accent.b], [90, 169, 240], "accent = #5aa9f0")

        let screen = components(WTTheme.light.screen)
        XCTAssertEqual([screen.r, screen.g, screen.b], [247, 251, 255], "screen = #f7fbff")
        XCTAssertFalse(WTTheme.light.isDark)
    }

    func testDarkThemeMatchesMockup() {
        let screen = components(WTTheme.dark.screen)
        XCTAssertEqual(screen.r, 12)
        XCTAssertEqual(screen.g, 21)
        XCTAssertEqual(screen.b, 36, "dark screen = #0c1524")
        XCTAssertTrue(WTTheme.dark.isDark)
    }

    func testCalendarFillScalesWithCompletion() {
        XCTAssertEqual(components(WTColor.calendarFill(pct: 0)).a, 1, accuracy: 0.01, "порожній день — суцільний сірий")
        XCTAssertEqual(components(WTColor.calendarFill(pct: 50)).a, 0.625, accuracy: 0.01)
        XCTAssertEqual(components(WTColor.calendarFill(pct: 100)).a, 1.0, accuracy: 0.01)
        XCTAssertEqual(
            components(WTColor.calendarFill(pct: 150)).a, 1.0, accuracy: 0.01,
            "понад 100 % насиченість не зростає"
        )
    }

    func testHeatmapHasFiveDistinctLevels() {
        let colors = (0...4).map { level -> String in
            let c = components(WTColor.heatmapFill(level: level))
            return "\(c.r),\(c.g),\(c.b),\(String(format: "%.2f", c.a))"
        }
        XCTAssertEqual(Set(colors).count, 5, "п'ять рівнів — п'ять різних кольорів")

        // Нульовий рівень — сірий трек, далі синій з наростанням прозорості.
        let blueOpacities = (1...4).map { components(WTColor.heatmapFill(level: $0)).a }
        XCTAssertEqual(blueOpacities.sorted(), blueOpacities, "інтенсивність зростає монотонно")
    }

    func testRadiiAndSpacingMatchMockup() {
        XCTAssertEqual(WTRadius.card, 24)
        XCTAssertEqual(WTRadius.sheet, 32)
        XCTAssertEqual(WTSpacing.screenTop, 64)
        XCTAssertEqual(WTSpacing.screenSideHome, 26, "1a має бічний відступ 26 pt")
        XCTAssertEqual(WTSpacing.screenSide, 24, "2e / 3f / 4a — 24 pt")
    }
}
