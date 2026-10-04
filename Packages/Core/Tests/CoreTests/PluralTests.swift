import XCTest
@testable import Core

final class PluralTests: XCTestCase {
    func testUkrainianForms() {
        let cases: [(Int, String)] = [
            (0, "днів"), (1, "день"), (2, "дні"), (4, "дні"), (5, "днів"), (11, "днів"),
            (12, "днів"), (14, "днів"), (21, "день"), (22, "дні"), (25, "днів"), (111, "днів"), (101, "день")
        ]
        for (n, expected) in cases {
            XCTAssertEqual(Plural.uk(n, one: "день", few: "дні", many: "днів"), expected, "n = \(n)")
        }
    }

    func testDaysIncludesNumber() {
        XCTAssertEqual(Plural.days(12), "12 днів")
        XCTAssertEqual(Plural.days(3), "3 дні")
    }
}
