import XCTest
import SwiftData
import Core
@testable import Persistence

/// Стирання з режиму розробника (WAT-68): «прогрес» лишає налаштування людини, «усе» — порожнє сховище.
@MainActor
final class DatabaseEraseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        try await super.setUp()
        container = Database.makeInMemoryContainer()
        let profiles = ProfileRepository(context: context)
        let profile = profiles.profile()
        profile.weightKg = 73
        profile.celebrationsSince = now
        profile.highestCelebratedLevel = 7
        profile.scheduleOfferShownAt = now
        profiles.setGoal(2400, source: .manual, effectiveFrom: DayKey(rawValue: "2026-10-01"), at: now)
        _ = profiles.quickAddPresets(.home)

        let dayLogs = DayLogRepository(context: context)
        let log = dayLogs.dayLog(for: DayKey(rawValue: "2026-10-20"), goalMl: 2400, timeZoneId: "Europe/Kyiv")
        dayLogs.insert(Intake(amountMl: 250, createdAt: now), into: log)
        context.insert(XPEntry(amount: 10, reason: .intake, dayKey: "2026-10-20", createdAt: now))
        context.insert(AchievementProgress(defKey: "first.glass", target: 1))
        context.insert(LearnProgress(storyId: "app.start", seenAt: now))
        try context.save()
    }

    private func count<T: PersistentModel>(_ model: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    func testEveryModelIsEitherProgressOrSettings() {
        let covered = Set((Database.progressModels + Database.settingsModels).map { String(describing: $0) })
        XCTAssertEqual(covered, Set(Database.schema.entities.map(\.name)),
                       "нова модель має потрапити в один зі списків — інакше скидання її пропустить")
    }

    func testProgressEraseKeepsSettingsAndResetsGameState() throws {
        try Database.erase(.progress, in: context)

        XCTAssertEqual(try count(DayLog.self), 0)
        XCTAssertEqual(try count(Intake.self), 0)
        XCTAssertEqual(try count(XPEntry.self), 0)
        XCTAssertEqual(try count(AchievementProgress.self), 0)
        XCTAssertEqual(try count(LearnProgress.self), 0)

        let profiles = ProfileRepository(context: context)
        XCTAssertEqual(profiles.profile().weightKg, 73, "налаштування людини лишаються")
        XCTAssertEqual(profiles.currentGoalMl(on: DayKey(rawValue: "2026-10-26")), 2400)
        XCTAssertGreaterThan(try count(QuickAddPreset.self), 0)
        XCTAssertNil(profiles.profile().celebrationsSince, "вікно відкриття — знову з першого запуску")
        XCTAssertEqual(profiles.profile().highestCelebratedLevel, 0)
        XCTAssertNil(profiles.profile().scheduleOfferShownAt)
    }

    func testEverythingEraseLeavesEmptyStore() throws {
        try Database.erase(.everything, in: context)

        for entity in Database.progressModels + Database.settingsModels {
            XCTAssertEqual(try count(entity), 0, "\(entity)")
        }
    }
}
