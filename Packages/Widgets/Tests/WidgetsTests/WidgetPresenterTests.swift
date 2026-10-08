import XCTest
import Core
@testable import Widgets

/// Тексти віджетів: на «ти», без роду, у форматах головного (SPEC-WIDGETS §8).
final class WidgetPresenterTests: XCTestCase {
    private func day(_ hour: Int, _ minute: Int, _ snapshot: WidgetSnapshot = Fixture.snapshot()) -> WidgetDay {
        WidgetDay.resolve(snapshot, at: Fixture.date(hour, minute), calendar: Fixture.calendar)
    }

    func testVolumeFormatsMatchHome() {
        XCTAssertEqual(WidgetPresenter.ringVolume(countedMl: 1250, goalMl: 2000), "1.25 / 2.0 л")
        XCTAssertEqual(WidgetPresenter.amount(500), "500 мл")
        XCTAssertEqual(WidgetPresenter.amount(1000), "1 л")
        XCTAssertEqual(WidgetPresenter.addTitle(1050), "+1.05 л")
        XCTAssertEqual(WidgetPresenter.left(626), "ще 650 мл")
        XCTAssertEqual(WidgetPresenter.liters(1000), "1")
    }

    func testPendingPart() {
        let part = WidgetPresenter.part(day(13, 25), xp: 10)
        XCTAssertEqual(part.kind, .pending)
        XCTAssertEqual(part.caption, "день")
        XCTAssertEqual(part.value, "650")
        XCTAssertEqual(part.unit, "мл")
        XCTAssertEqual(part.headline, "ще до 17:00")
        XCTAssertEqual(part.footnote, "3 год 35 хв")
        XCTAssertEqual(part.xp, "+10 XP")
    }

    func testClosedPartTellsWhatIsNext() {
        let part = WidgetPresenter.part(day(11, 45), xp: 10)
        XCTAssertEqual(part.kind, .closed)
        XCTAssertEqual(part.headline, "Ранок і полудень закрито")
        XCTAssertEqual(part.footnote, "далі день — 826 мл")
        XCTAssertNil(part.xp)
    }

    func testGoalMetAndNight() {
        let full = Fixture.snapshot(portions: [Fixture.portion(9, 0, 1000, id: 1), Fixture.portion(12, 0, 1000, id: 2)])
        XCTAssertEqual(WidgetPresenter.part(day(13, 0, full), xp: 10).kind, .goalMet)
        XCTAssertEqual(WidgetPresenter.part(day(7, 0), xp: 10).value, "08:00")
        XCTAssertEqual(WidgetPresenter.part(day(22, 30), xp: 10).caption, "Добраніч")
    }

    /// «Просто норма за день» (WAT-42): ціль — уся норма, дедлайн — відбій, без XP.
    func testWholeDayWithoutRhythm() {
        let part = WidgetPresenter.part(day(13, 25, Fixture.snapshot(rhythm: false)), xp: 10)
        XCTAssertEqual(part.kind, .wholeDay)
        XCTAssertEqual(part.value, "1")
        XCTAssertEqual(part.unit, "л")
        XCTAssertEqual(part.headline, "ще до 22:00")
        XCTAssertNil(part.xp)
    }

    func testPaceLine() {
        XCTAssertEqual(WidgetPresenter.pace(day(13, 25)), "+100 мл до темпу")
        let behind = Fixture.snapshot(portions: [Fixture.portion(8, 20, 250, id: 1), Fixture.portion(9, 50, 200, id: 2)])
        XCTAssertEqual(WidgetPresenter.pace(day(12, 40, behind)), "відстаєш на 350 мл")
    }

    func testReserveTexts() throws {
        let reserve = HydrationReserve.make(portions: Fixture.aheadPortions, capacityMl: 500, now: Fixture.date(13, 25),
                                            plannedReminder: nil, previous: nil, zero: Fixture.paceZero())
        let snapshot = Fixture.snapshot(reserve: reserve)
        XCTAssertEqual(WidgetPresenter.reserve(day(13, 25, snapshot)),
                       .init(headline: "Пий о 15:24", footnote: "запасу ~1 год 49 хв", isUrgent: false))
        // Нагадування за темпом, не з плану (сповіщення вимкнено) — «нагадаю» було б неправдою.
        XCTAssertEqual(WidgetPresenter.reserve(day(15, 20, snapshot)),
                       .init(headline: "Час пити", footnote: "запас порожній", isUrgent: true))
        let planned = HydrationReserve.make(portions: Fixture.aheadPortions, capacityMl: 500, now: Fixture.date(13, 25),
                                            plannedReminder: Fixture.date(15, 24), previous: nil, zero: Fixture.paceZero())
        XCTAssertEqual(WidgetPresenter.reserve(day(15, 20, Fixture.snapshot(reserve: planned))),
                       .init(headline: "Час пити", footnote: "нагадаю о 15:24", isUrgent: true))
        XCTAssertEqual(WidgetPresenter.reserve(day(8, 30, Fixture.snapshot(portions: []))).headline, "Почни зі склянки")
        XCTAssertEqual(WidgetPresenter.reserve(day(23, 0, snapshot)).headline, "Добраніч")
    }

    func testInlineAndStreakWord() {
        XCTAssertEqual(WidgetPresenter.inline(day(13, 25)), "💧 1 з 2 л · ще 1 л")
        XCTAssertEqual(WidgetPresenter.streakWord(12), "днів поспіль")
        XCTAssertEqual(WidgetPresenter.streakWord(22), "дні поспіль")
        XCTAssertEqual(WidgetPresenter.streakWord(1), "день поспіль")
    }

    /// Підйом о 06:00 — ранок 06–09 довший за 2 год і має власну ціль, не зливається з полуднем.
    func testEarlyWakeHasOwnMorningBlock() {
        let early = WidgetSnapshot.Schedule(wakeMinutes: 6 * 60, sleepMinutes: 22 * 60)
        var snapshot = Fixture.snapshot(portions: [])
        snapshot.schedule = early
        let part = WidgetPresenter.part(day(6, 30, snapshot), xp: 10)
        XCTAssertEqual(part.caption, "ранок")
    }
}
