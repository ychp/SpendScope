import Foundation
import SQLite3

/// Old identifiers are retained only to import existing installations once.
enum AppIdentityMigration {
    static let legacyName = "SpendScope"
    static let bundleID = "com.ychp.CodexVista"
    private static let preferencesMigrationKey = "migration.legacyPreferences.v1"

    static func migratePreferences(
        defaults: UserDefaults = .standard,
        destinationDomain: String = bundleID,
        legacyDomain: String = "com.ychp.SpendScope"
    ) {
        var destination = defaults.persistentDomain(forName: destinationDomain) ?? [:]
        guard destination[preferencesMigrationKey] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        let keys = [
            AppPreferenceKeys.colorScheme,
            AppPreferenceKeys.keepsDashboardOnTop,
            AppPreferenceKeys.dashboardCloseBehavior,
            AppPreferenceKeys.automaticRefreshEnabled,
            AppPreferenceKeys.usageRemindersEnabled,
            AppPreferenceKeys.remindsAtTwentyPercent,
            AppPreferenceKeys.remindsAtTenPercent,
            AppPreferenceKeys.remindsAtFivePercent,
            AppPreferenceKeys.usageReminderCheckpoint,
            AppPreferenceKeys.showsLivePreview,
            AppPreferenceKeys.summaryPlacement,
            AppPreferenceKeys.showsResetCountdown,
            AppPreferenceKeys.quotaDisplay,
            AppPreferenceKeys.firstSubscriptionDate,
            AppPreferenceKeys.automaticallyChecksForUpdates,
            AppPreferenceKeys.automaticallyDownloadsUpdates
        ]
        for key in keys where destination[key] == nil {
            destination[key] = legacy[key]
        }
        destination[preferencesMigrationKey] = true
        defaults.setPersistentDomain(destination, forName: destinationDomain)
    }

    static func prepareDatabase(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = applicationSupportURL.appendingPathComponent("CodexVista", isDirectory: true)
        let destination = directory.appendingPathComponent("CodexVista.sqlite")
        guard !fileManager.fileExists(atPath: destination.path) else { return destination }
        let source = applicationSupportURL
            .appendingPathComponent(legacyName, isDirectory: true)
            .appendingPathComponent("\(legacyName).sqlite")
        guard fileManager.fileExists(atPath: source.path) else { return destination }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let snapshot = staging.appendingPathComponent("CodexVista.sqlite")
        // SQLite backup includes committed WAL data even if the old app is running.
        // Publish only a complete, closed snapshot; leave the old database intact.
        try backupDatabase(from: source, to: snapshot)
        try fileManager.moveItem(at: snapshot, to: destination)
        return destination
    }

    private static func backupDatabase(from source: URL, to destination: URL) throws {
        var sourceHandle: OpaquePointer?
        let sourceResult = sqlite3_open_v2(source.path, &sourceHandle, SQLITE_OPEN_READONLY, nil)
        defer { if let sourceHandle { sqlite3_close_v2(sourceHandle) } }
        guard sourceResult == SQLITE_OK, let sourceHandle else {
            throw migrationError(sourceResult)
        }
        sqlite3_busy_timeout(sourceHandle, 3_000)

        var destinationHandle: OpaquePointer?
        let destinationResult = sqlite3_open_v2(
            destination.path, &destinationHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        )
        defer { if let destinationHandle { sqlite3_close_v2(destinationHandle) } }
        guard destinationResult == SQLITE_OK, let destinationHandle else {
            throw migrationError(destinationResult)
        }
        guard let backup = sqlite3_backup_init(destinationHandle, "main", sourceHandle, "main") else {
            throw migrationError(sqlite3_errcode(destinationHandle))
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE else { throw migrationError(stepResult) }
        guard finishResult == SQLITE_OK else { throw migrationError(finishResult) }
        // Ensure the snapshot is self-contained before moving it out of staging.
        let journalResult = sqlite3_exec(destinationHandle, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        guard journalResult == SQLITE_OK else { throw migrationError(journalResult) }
    }

    private static func migrationError(_ code: Int32) -> SQLiteDatabaseError {
        SQLiteDatabaseError(code: code, message: "无法迁移旧版应用的统计数据。", sql: nil)
    }
}
