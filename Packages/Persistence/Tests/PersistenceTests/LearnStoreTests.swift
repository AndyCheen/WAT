import XCTest
import SwiftData
@testable import Persistence

@MainActor
final class LearnStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: LearnStore!
    private let now = Date(timeIntervalSince1970: 1_784_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = Database.makeInMemoryContainer()
        store = LearnStore(context: container.mainContext)
    }

    func testFirstVisitMarksStoriesSeenOnce() {
        XCTAssertFalse(store.hasVisited)
        store.markSeen(["why", "xp"], at: now)
        store.markSeen(["why", "xp", "new"], at: now.addingTimeInterval(60))

        XCTAssertTrue(store.hasVisited)
        XCTAssertEqual(store.progress("why")?.seenAt, now, "повторний показ дату першого не переписує")
        XCTAssertEqual(store.progress("new")?.seenAt, now.addingTimeInterval(60))
    }

    func testSlideIsRememberedAndResetOnFinish() {
        store.saveSlide(3, of: "why", at: now)
        XCTAssertEqual(store.progress("why")?.lastSlide, 3, "контекстний вхід повз бібліотеку теж створює рядок")

        XCTAssertTrue(store.complete("why", at: now))
        XCTAssertEqual(store.progress("why")?.lastSlide, 0, "прочитана відкривається з початку (§6)")
        XCTAssertFalse(store.complete("why", at: now.addingTimeInterval(3600)), "друге прочитання — не перше")
        XCTAssertEqual(store.progress("why")?.completedAt, now)
    }

    func testProgressSurvivesNewStoreOnSameContainer() {
        store.saveSlide(2, of: "xp", at: now)
        let reopened = LearnStore(context: container.mainContext)
        XCTAssertEqual(reopened.progress("xp")?.lastSlide, 2)
    }
}
