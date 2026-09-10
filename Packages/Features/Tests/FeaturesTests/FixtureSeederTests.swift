import XCTest
import SwiftData
import Core
import Persistence
import Hydration
@testable import Features

/// Демо-дані мають бути однакові в кожному запуску процесу.
///
/// Раніше патерн дня вибирався за `String.hashValue`, а він у Swift засівається
/// випадково при старті процесу: три однакові прогони з тим самим `FixedClock`
/// давали серії 0, 2 і 1. Скріншоти для дизайн-QA не збігалися між собою, а e2e,
/// що спираються на вміст демо-історії, були приречені плавати. Цей тест ловить
/// повернення будь-якої нестабільної функції від `dayKey` — у межах одного
/// процесу, бо між процесами XCTest порівняти не може.
@MainActor
final class FixtureSeederTests: XCTestCase {

    private static let days = 40

    private static func date(day: Int, hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = day; c.hour = hour
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return cal.date(from: c)!
    }

    /// Кожен виклик — окрема in-memory БД з тим самим годинником.
    private func seededServices() -> AppServices {
        let services = AppServices(
            container: Database.makeInMemoryContainer(),
            clock: FixedClock(now: Self.date(day: 18, hour: 22))
        )
        services.bootstrap()
        FixtureSeeder.seed(into: services, days: Self.days)
        return services
    }

    private func history(of services: AppServices) -> [DayKey: Int] {
        let today = services.calendar.today
        var result: [DayKey: Int] = [:]
        for offset in 1...Self.days {
            let day = services.calendar.dayKey(offsetDays: -offset, from: today)
            result[day] = services.hydration.snapshot(for: day).totalMl
        }
        return result
    }

    func testSeedIsDeterministicAcrossRuns() {
        let first = seededServices()
        let second = seededServices()

        XCTAssertEqual(history(of: first), history(of: second), "обсяги по днях розійшлися")
        XCTAssertEqual(
            history(of: first).filter { $0.value >= 2000 }.keys.sorted(),
            history(of: second).filter { $0.value >= 2000 }.keys.sorted(),
            "набір днів із закритою нормою розійшовся"
        )
        XCTAssertEqual(
            first.gamification.streakSummary().current,
            second.gamification.streakSummary().current,
            "серія розійшлася — саме це давало хибний баг-репорт"
        )
        XCTAssertEqual(
            first.gamification.levelProgress().totalXp,
            second.gamification.levelProgress().totalXp
        )
    }

    /// Єдина перевірка, що справді ловить повернення `hashValue`: XCTest живе в одному
    /// процесі, і всередині нього `hashValue` теж стабільний — тест на дві бази пройшов
    /// би й зі старим кодом. Тому прибиваємо самі числа хешу.
    func testStableHashIsPinnedToKnownValues() {
        XCTAssertEqual(FixtureSeeder.stableHash("2026-07-18"), 12_381_657_508_597_159_859)
        XCTAssertEqual(FixtureSeeder.stableHash("2026-01-01"), 18_099_244_625_767_376_899)
        XCTAssertEqual(FixtureSeeder.stableHash("1970-01-01"), 8_492_760_844_693_528_672)
    }

    /// Фіксуємо не лише збіг двох прогонів, а й самі числа: якщо стабільну функцію
    /// підмінять іншою (теж стабільною), демо-історія зміниться мовчки.
    func testSeedKeepsExpectedShape() {
        let services = seededServices()
        let days = history(of: services)

        let skipped = days.filter { $0.value == 0 }
        let met = days.filter { $0.value >= 2000 }

        XCTAssertEqual(days.count, Self.days)
        XCTAssertEqual(skipped.count, 4, "≈ кожен 9-й день пропущений")
        XCTAssertEqual(met.count, 23, "≈ 2 з 3 непропущених днів закривають норму")
    }
}
