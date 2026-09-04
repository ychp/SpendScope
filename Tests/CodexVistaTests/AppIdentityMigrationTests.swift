import Foundation
import XCTest
@testable import CodexVista

final class AppIdentityMigrationTests: XCTestCase {
    func testMigrationPreservesCommittedWALDataAndDoesNotOverwriteNewDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyDirectory = root.appendingPathComponent(AppIdentityMigration.legacyName)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appendingPathComponent("\(AppIdentityMigration.legacyName).sqlite")
        let legacy = try SQLiteDatabase(url: legacyURL)
        _ = try legacy.query(sql: "PRAGMA journal_mode=WAL")
        _ = try legacy.query(sql: "PRAGMA wal_autocheckpoint=0")
        try legacy.execute(sql: "CREATE TABLE fixture (tokens INTEGER)")
        try legacy.execute(sql: "INSERT INTO fixture VALUES (123)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path + "-wal"))

        let migratedURL = try AppIdentityMigration.prepareDatabase(applicationSupportURL: root)
        XCTAssertEqual(migratedURL.lastPathComponent, "CodexVista.sqlite")
        let migrated = try SQLiteDatabase(url: migratedURL)
        XCTAssertEqual(try migrated.query(sql: "SELECT tokens FROM fixture").first?["tokens"], .integer(123))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

        try migrated.execute(sql: "INSERT INTO fixture VALUES (456)")
        try legacy.execute(sql: "INSERT INTO fixture VALUES (789)")
        XCTAssertEqual(try AppIdentityMigration.prepareDatabase(applicationSupportURL: root), migratedURL)
        XCTAssertEqual(try migrated.query(sql: "SELECT tokens FROM fixture ORDER BY tokens").map { $0["tokens"] }, [.integer(123), .integer(456)])
    }

    func testFreshInstallDoesNotCreateAnEmptyMigrationDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = try AppIdentityMigration.prepareDatabase(applicationSupportURL: root)
        XCTAssertEqual(destination.lastPathComponent, "CodexVista.sqlite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFailedMigrationLeavesNoDestinationAndCanBeRetried() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(AppIdentityMigration.legacyName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("\(AppIdentityMigration.legacyName).sqlite")
        try Data("invalid database".utf8).write(to: source)
        XCTAssertThrowsError(try AppIdentityMigration.prepareDatabase(applicationSupportURL: root))
        let destinationDirectory = root.appendingPathComponent("CodexVista")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path), [])
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "invalid database")
        try FileManager.default.removeItem(at: source)
        let repaired = try SQLiteDatabase(url: source)
        try repaired.execute(sql: "CREATE TABLE fixture (tokens INTEGER)")
        let destination = try AppIdentityMigration.prepareDatabase(applicationSupportURL: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testPreferencesMergeOnlyOnceAndKeepCurrentValues() throws {
        let domain = "CodexVistaMigrationTests.\(UUID().uuidString)"
        let legacyDomain = domain + ".legacy"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer {
            defaults.removePersistentDomain(forName: domain)
            defaults.removePersistentDomain(forName: legacyDomain)
        }
        defaults.setPersistentDomain([
            AppPreferenceKeys.colorScheme: "dark",
            AppPreferenceKeys.automaticRefreshEnabled: false,
            AppPreferenceKeys.firstSubscriptionDate: 123456.0,
            "unrelated": "ignore"
        ], forName: legacyDomain)
        defaults.set("light", forKey: AppPreferenceKeys.colorScheme)
        AppIdentityMigration.migratePreferences(defaults: defaults, destinationDomain: domain, legacyDomain: legacyDomain)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.colorScheme), "light")
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKeys.automaticRefreshEnabled) as? Bool, false)
        XCTAssertEqual(defaults.double(forKey: AppPreferenceKeys.firstSubscriptionDate), 123456.0)
        XCTAssertNil(defaults.object(forKey: "unrelated"))
        defaults.removeObject(forKey: AppPreferenceKeys.firstSubscriptionDate)
        AppIdentityMigration.migratePreferences(defaults: defaults, destinationDomain: domain, legacyDomain: legacyDomain)
        XCTAssertNil(defaults.object(forKey: AppPreferenceKeys.firstSubscriptionDate))
        XCTAssertEqual(defaults.persistentDomain(forName: legacyDomain)?[AppPreferenceKeys.colorScheme] as? String, "dark")
    }
}
