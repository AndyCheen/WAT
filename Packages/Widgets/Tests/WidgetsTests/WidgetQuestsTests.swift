import XCTest
import Core
@testable import Widgets

/// Права половина «Прогресу» (SPEC-QUESTS §9.3): стани, дедлайни без нового знімка, старий знімок.
final class WidgetQuestsTests: XCTestCase {
    private typealias Quest = WidgetSnapshot.Quest

    private static let half = Quest(title: "Половина до 14:00", progressLabel: "ще 50 мл", fraction: 0.95, isDone: false,
                                    expiresAt: Fixture.date(14, 0))
    private static let glasses = Quest(title: "5 склянок від 150 мл", progressLabel: "4/5", fraction: 0.8, isDone: false)
    private static let wake = Quest(title: "Склянка після підйому", progressLabel: "Готово", fraction: 1, isDone: true,
                                    expiresAt: Fixture.date(8, 0))
    private static let week = Quest(title: "Норма 5 днів", progressLabel: "2/5 дн.", fraction: 0.4, isDone: false)

    private func snapshot(daily: [Quest], weekly: [Quest] = [week], expired: Int? = nil,
                          startsMonday: Bool? = nil) -> WidgetSnapshot {
        var snapshot = Fixture.snapshot()
        snapshot.dailyQuests = daily
        snapshot.weeklyQuests = weekly
        snapshot.expiredDailyQuests = expired
        snapshot.weeklyStartsMonday = startsMonday
        return snapshot
    }

    func testOpenRowsOnlyAndOneWeekly() {
        let quests = WidgetPresenter.quests(snapshot(daily: [Self.wake, Self.half, Self.glasses]), at: Fixture.date(13, 25))
        XCTAssertEqual(quests.today, .rows([Self.half, Self.glasses]), "виконаного рядка немає — місця три рядки")
        XCTAssertEqual(quests.week, .row(Self.week))
    }

    /// Дедлайн минув між знімками — рядок зникає сам, і «✓ Усе на сьогодні» не з'являється.
    func testDeadlinePassesWithoutNewSnapshot() {
        let snapshot = snapshot(daily: [Self.wake, Self.half])
        XCTAssertEqual(WidgetPresenter.quests(snapshot, at: Fixture.date(13, 59)).today, .rows([Self.half]))
        XCTAssertEqual(WidgetPresenter.quests(snapshot, at: Fixture.date(14, 0)).today, .hidden)
    }

    func testAllDoneOnlyWithoutExpired() {
        XCTAssertEqual(WidgetPresenter.quests(snapshot(daily: [Self.wake]), at: Fixture.date(13, 25)).today, .allDone)
        XCTAssertEqual(WidgetPresenter.quests(snapshot(daily: [Self.wake], expired: 1), at: Fixture.date(13, 25)).today,
                       .hidden, "одне зникло за дедлайном — не «усе»")
        XCTAssertEqual(WidgetPresenter.quests(snapshot(daily: []), at: Fixture.date(13, 25)).today, .hidden)
    }

    func testWeekStates() {
        var done = Self.week
        done.isDone = true
        XCTAssertEqual(WidgetPresenter.quests(snapshot(daily: [], weekly: [done]), at: Fixture.date(13, 25)).week, .closed)
        XCTAssertEqual(WidgetPresenter.quests(snapshot(daily: [], weekly: [], startsMonday: true),
                                              at: Fixture.date(13, 25)).week, .fromMonday)
        XCTAssertEqual(WidgetPresenter.quests(snapshot(daily: [], weekly: []), at: Fixture.date(13, 25)).week, .hidden)
    }

    /// Запис таймлайну — на дедлайн невиконаного щоденного, лише в «Прогресі» й лише для доби знімка.
    func testTimelineHasDeadlineEntries() {
        let snapshot = snapshot(daily: [Self.wake, Self.half])
        let progress = WidgetTimeline.dates(for: .progress, snapshot: snapshot, from: Fixture.date(13, 25),
                                            calendar: Fixture.calendar)
        XCTAssertTrue(progress.contains(Fixture.date(14, 0)))
        let today = WidgetTimeline.dates(for: .today, snapshot: snapshot, from: Fixture.date(13, 25), calendar: Fixture.calendar)
        XCTAssertFalse(today.contains(Fixture.date(14, 0)), "іншим віджетам цей запис нічого не змінює")
    }

    /// Знімок збірки до WAT-64 у App Group — без дедлайнів і нових полів — читається.
    func testSnapshotWithoutNewFieldsDecodes() throws {
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: encoder.encode(snapshot(daily: [Self.half], expired: 1, startsMonday: false))) as? [String: Any])
        object["expiredDailyQuests"] = nil
        object["weeklyStartsMonday"] = nil
        object["dailyQuests"] = [["title": "Половина до 14:00", "progressLabel": "ще 50 мл", "fraction": 0.95, "isDone": false]]
        let old = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.dailyQuests.first?.expiresAt)
        XCTAssertNil(old.expiredDailyQuests)
        XCTAssertEqual(WidgetPresenter.quests(old, at: Fixture.date(23, 0)).today, .rows([old.dailyQuests[0]]))
    }
}
