import XCTest
import Core
import Persistence
@testable import Notifications

/// Зразки сповіщень режиму розробника (WAT-68): кожна ситуація — з текстом, діями й переходом, як у плані, і поза
/// диффом планувальника.
final class NotificationSampleTests: XCTestCase {
    private let now = Fixture.date(15, 20)

    private func sample(_ kind: NotificationSample, context: NotificationContext? = nil) -> PlannedNotification {
        NotificationPlanner.sample(kind, fireAt: now.addingTimeInterval(5),
                                   context: context ?? Fixture.context(at: now, countedMl: 900),
                                   preferences: .default)
    }

    func testEverySampleHasCopyAndStaysOutsideThePlanDiff() {
        for kind in NotificationSample.allCases {
            let item = sample(kind)
            XCTAssertEqual(item.type, kind.type, "\(kind)")
            XCTAssertFalse(item.title.isEmpty, "\(kind)")
            XCTAssertFalse(item.body.isEmpty, "\(kind)")
            XCTAssertFalse(item.title.contains("{") || item.body.contains("{"), "плейсхолдер не заповнено: \(item.body)")
            XCTAssertLessThanOrEqual(item.title.count, 30, item.title)
            XCTAssertLessThanOrEqual(item.body.count, 100, item.body)
            XCTAssertTrue(item.id.hasPrefix("debug."), "\(kind): \(item.id)")
            XCTAssertFalse(NotificationScheduler.isManaged(item.id), "наступне перепланування його не зніме")
        }
    }

    func testSamplesCarryTheirActionsAndRoutes() {
        XCTAssertEqual(sample(.reminder).category, .reminder)
        XCTAssertEqual(sample(.morning).tapRoute, .glass)
        XCTAssertEqual(sample(.rescueEvening).tapRoute, .freezeCard)
        XCTAssertEqual(sample(.eveningClose).category, .close)
        XCTAssertEqual(sample(.eveningClose).actionMl, 600, "залишок 1100 мл — дія до межі 600")
        XCTAssertTrue(sample(.reportWeek).isSilent)
    }

    func testClosedDayStillAsksForAGlass() {
        let item = sample(.eveningClosable, context: Fixture.context(at: now, countedMl: 2000))
        XCTAssertTrue(item.body.contains("250 мл"), "щонайменше склянка, а не «ще 0 мл»: \(item.body)")
    }
}
