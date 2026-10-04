import XCTest
@testable import Core

final class StableHashTests: XCTestCase {
    /// Єдина перевірка, що справді ловить повернення `hashValue`: XCTest живе в одному
    /// процесі, і всередині нього `hashValue` теж стабільний — тест на дві бази пройшов
    /// би й зі старим кодом. Тому прибиваємо самі числа хешу.
    func testStableHashIsPinnedToKnownValues() {
        XCTAssertEqual(StableHash.fnv1a("2026-07-18"), 12_381_657_508_597_159_859)
        XCTAssertEqual(StableHash.fnv1a("2026-01-01"), 18_099_244_625_767_376_899)
        XCTAssertEqual(StableHash.fnv1a("1970-01-01"), 8_492_760_844_693_528_672)
    }
}
