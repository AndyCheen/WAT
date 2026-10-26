import XCTest
import SwiftData
@testable import Persistence

/// Сховище на диску між запусками (WAT-67): дані переживають повторне відкриття, а перед першим відкриттям зміненої
/// схеми лишається копія файлів.
@MainActor
final class DatabaseStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private var storeURL: URL { directory.appendingPathComponent("WaterTracker.store") }

    func testDataSurvivesReopeningTheStore() throws {
        do {
            let container = try Database.makeContainer(url: storeURL)
            ProfileRepository(context: container.mainContext).profile().weightKg = 73
            try container.mainContext.save()
        }
        let reopened = try Database.makeContainer(url: storeURL)
        XCTAssertEqual(ProfileRepository(context: reopened.mainContext).profile().weightKg, 73)
    }

    func testFirstLaunchRemembersSchemaWithoutBackup() {
        XCTAssertNil(Database.backupIfSchemaChanged(storeURL: storeURL, fingerprint: "a", defaults: defaults, now: now),
                     "сховища ще немає — копіювати нічого")
        XCTAssertEqual(defaults.string(forKey: Database.fingerprintKey), "a")
    }

    func testChangedSchemaCopiesStoreOnce() throws {
        _ = try Database.makeContainer(url: storeURL)
        defaults.set("old", forKey: Database.fingerprintKey)

        let backup = try XCTUnwrap(Database.backupIfSchemaChanged(storeURL: storeURL, fingerprint: "new",
                                                                  defaults: defaults, now: now))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("WaterTracker.store").path))
        XCTAssertNil(Database.backupIfSchemaChanged(storeURL: storeURL, fingerprint: "new", defaults: defaults, now: now),
                     "та сама схема — друга копія не потрібна")
    }

    func testOnlyLatestBackupsAreKept() throws {
        _ = try Database.makeContainer(url: storeURL)
        for index in 0..<5 {
            Database.backupIfSchemaChanged(storeURL: storeURL, fingerprint: "v\(index)", defaults: defaults,
                                           now: now.addingTimeInterval(Double(index)))
        }
        let backups = directory.appendingPathComponent("Backups")
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        XCTAssertEqual(names.count, Database.backupsKept)
        XCTAssertTrue(names.last?.hasSuffix("-v4") == true, "лишаються найсвіжіші")
    }

    func testFingerprintIsStableAndReflectsModels() {
        XCTAssertEqual(Database.fingerprint(), Database.fingerprint())
        XCTAssertNotEqual(Database.fingerprint(), Database.fingerprint(of: Schema([UserProfile.self])))
    }
}
