import CryptoKit
import Foundation
import SQLite3

struct RolloutFile: Equatable, Sendable {
    let fileID: String
    let deviceID: UInt64
    let inode: UInt64
    let url: URL
    let fileSize: Int64
    let modificationTimeMilliseconds: Int64
    let isArchived: Bool
    let thread: ThreadIndexRecord?
}

struct ThreadIndexRecord: Equatable, Sendable {
    let threadID: String
    let rolloutPath: String
    let sourceRaw: String
    let model: String?
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let archived: Bool
    let childEdgeStatus: String?
}

enum CodexIndexHealth: Equatable, Sendable {
    case available
    case missing
    case degraded(String)
}

struct CodexSourceInventory: Equatable, Sendable {
    let rollouts: [RolloutFile]
    let threadIndex: [ThreadIndexRecord]
    let indexHealth: CodexIndexHealth
}

struct CodexSourceDiscovery {
    private let fileManager: FileManager
    private let indexReader: CodexThreadIndexReader

    init(
        fileManager: FileManager = .default,
        indexReader: CodexThreadIndexReader = CodexThreadIndexReader()
    ) {
        self.fileManager = fileManager
        self.indexReader = indexReader
    }

    func discover(rootURL: URL) throws -> CodexSourceInventory {
        let indexResult = readIndex(at: rootURL)
        var recordsByPath: [String: ThreadIndexRecord] = [:]
        for record in indexResult.records {
            recordsByPath[canonicalPath(record.rolloutPath)] = record
        }

        let sessionsURL = rootURL.appending(path: "sessions", directoryHint: .isDirectory)
        let archiveURL = rootURL.appending(path: "archived_sessions", directoryHint: .isDirectory)
        let activeURLs = try recursiveJSONLFiles(at: sessionsURL)
        let archivedURLs = try directJSONLFiles(at: archiveURL)

        var rollouts: [RolloutFile] = []
        rollouts.reserveCapacity(activeURLs.count + archivedURLs.count)
        for url in activeURLs {
            rollouts.append(try rollout(url: url, isArchived: false, recordsByPath: recordsByPath))
        }
        for url in archivedURLs {
            rollouts.append(try rollout(url: url, isArchived: true, recordsByPath: recordsByPath))
        }
        rollouts.sort { $0.url.path < $1.url.path }

        return CodexSourceInventory(
            rollouts: rollouts,
            threadIndex: indexResult.records,
            indexHealth: indexResult.health
        )
    }

    private func readIndex(at rootURL: URL) -> (records: [ThreadIndexRecord], health: CodexIndexHealth) {
        guard let databaseURL = newestStateDatabase(in: rootURL) else {
            return ([], .missing)
        }

        do {
            let records = try indexReader.read(databaseURL: databaseURL)
            return (records, .available)
        } catch let error as CodexThreadIndexError {
            return ([], .degraded(error.description))
        } catch {
            return ([], .degraded("index read failed"))
        }
    }

    private func newestStateDatabase(in rootURL: URL) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return entries.compactMap { url -> (url: URL, suffix: String)? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else { return nil }
            let start = name.index(name.startIndex, offsetBy: "state_".count)
            let end = name.index(name.endIndex, offsetBy: -".sqlite".count)
            let suffix = String(name[start..<end])
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
            let normalized = String(suffix.drop(while: { $0 == "0" }))
            return (url, normalized.isEmpty ? "0" : normalized)
        }.max { lhs, rhs in
            if lhs.suffix.count != rhs.suffix.count {
                return lhs.suffix.count < rhs.suffix.count
            }
            return lhs.suffix < rhs.suffix
        }?.url
    }

    private func recursiveJSONLFiles(at directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        var traversalError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw CodexSourceDiscoveryError.unreadableDirectory
        }

        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { result.append(url) }
        }
        if let traversalError { throw traversalError }
        return result
    }

    private func directJSONLFiles(at directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func rollout(
        url: URL,
        isArchived: Bool,
        recordsByPath: [String: ThreadIndexRecord]
    ) throws -> RolloutFile {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let size = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            throw CodexSourceDiscoveryError.missingFileAttributes
        }
        let milliseconds = modificationDate.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            throw CodexSourceDiscoveryError.invalidModificationDate
        }

        let deviceID = device.uint64Value
        let inodeValue = inode.uint64Value
        let path = canonicalPath(url.path)
        let thread = recordsByPath[path]
        let identity = "\(path)|\(thread?.threadID ?? "unindexed")"
        let fileID = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return RolloutFile(
            fileID: fileID,
            deviceID: deviceID,
            inode: inodeValue,
            url: url,
            fileSize: size.int64Value,
            modificationTimeMilliseconds: Int64(milliseconds.rounded()),
            isArchived: isArchived,
            thread: thread
        )
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

enum CodexSourceDiscoveryError: Error {
    case unreadableDirectory
    case missingFileAttributes
    case invalidModificationDate
}

struct CodexThreadIndexReader {
    func read(databaseURL: URL) throws -> [ThreadIndexRecord] {
        var optionalDatabase: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &optionalDatabase,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database = optionalDatabase else {
            if let optionalDatabase { sqlite3_close_v2(optionalDatabase) }
            throw CodexThreadIndexError.openFailed(openResult)
        }
        defer { sqlite3_close_v2(database) }

        let timeoutResult = sqlite3_busy_timeout(database, 100)
        guard timeoutResult == SQLITE_OK else {
            throw CodexThreadIndexError.busyTimeoutFailed(timeoutResult)
        }

        let threadColumns = try columns(in: "threads", database: database)
        guard !threadColumns.isEmpty else {
            throw CodexThreadIndexError.missingTable("threads")
        }
        let requiredThreadColumns: Set<String> = ["id", "rollout_path", "source", "archived"]
        var missingThreadColumns = requiredThreadColumns.subtracting(threadColumns).sorted()
        if threadColumns.isDisjoint(with: ["created_at_ms", "created_at"]) {
            missingThreadColumns.append("created_at_ms|created_at")
        }
        if threadColumns.isDisjoint(with: ["updated_at_ms", "updated_at"]) {
            missingThreadColumns.append("updated_at_ms|updated_at")
        }
        guard missingThreadColumns.isEmpty else {
            throw CodexThreadIndexError.missingColumns(table: "threads", columns: missingThreadColumns)
        }

        let edgeColumns = try columns(in: "thread_spawn_edges", database: database)
        if !edgeColumns.isEmpty {
            let requiredEdgeColumns: Set<String> = ["child_thread_id", "status"]
            let missingEdgeColumns = requiredEdgeColumns.subtracting(edgeColumns).sorted()
            guard missingEdgeColumns.isEmpty else {
                throw CodexThreadIndexError.missingColumns(
                    table: "thread_spawn_edges",
                    columns: missingEdgeColumns
                )
            }
        }

        let usesMillisecondCreatedAt = threadColumns.contains("created_at_ms")
        let usesMillisecondUpdatedAt = threadColumns.contains("updated_at_ms")
        let modelExpression = threadColumns.contains("model") ? "model" : "NULL"
        let createdExpression = usesMillisecondCreatedAt ? "created_at_ms" : "created_at"
        let updatedExpression = usesMillisecondUpdatedAt ? "updated_at_ms" : "updated_at"
        let sql = """
            SELECT id, rollout_path, source, \(modelExpression) AS model,
                   \(createdExpression) AS created_value,
                   \(updatedExpression) AS updated_value, archived
            FROM threads ORDER BY id
            """
        var records = try readThreads(
            database: database,
            sql: sql,
            createdAtIsMilliseconds: usesMillisecondCreatedAt,
            updatedAtIsMilliseconds: usesMillisecondUpdatedAt
        )

        guard !edgeColumns.isEmpty, !records.isEmpty else { return records }
        let statuses = try readEdgeStatuses(
            database: database,
            knownThreadIDs: Set(records.map(\.threadID))
        )
        records = records.map { record in
            ThreadIndexRecord(
                threadID: record.threadID,
                rolloutPath: record.rolloutPath,
                sourceRaw: record.sourceRaw,
                model: record.model,
                createdAtMilliseconds: record.createdAtMilliseconds,
                updatedAtMilliseconds: record.updatedAtMilliseconds,
                archived: record.archived,
                childEdgeStatus: statuses[record.threadID]
            )
        }
        return records
    }

    private func columns(in table: String, database: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CodexThreadIndexError.queryFailed(prepareResult, context: "inspect \(table)")
        }
        defer { sqlite3_finalize(statement) }

        var result: Set<String> = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let pointer = sqlite3_column_text(statement, 1) else {
                    throw CodexThreadIndexError.invalidValue("\(table).column")
                }
                result.insert(String(cString: pointer))
            case SQLITE_DONE:
                return result
            case let code:
                throw CodexThreadIndexError.queryFailed(code, context: "inspect \(table)")
            }
        }
    }

    private func readThreads(
        database: OpaquePointer,
        sql: String,
        createdAtIsMilliseconds: Bool,
        updatedAtIsMilliseconds: Bool
    ) throws -> [ThreadIndexRecord] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CodexThreadIndexError.queryFailed(prepareResult, context: "read threads")
        }
        defer { sqlite3_finalize(statement) }

        var records: [ThreadIndexRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let created = try requiredInteger(statement, column: 4, name: "threads.created_at")
                let updated = try requiredInteger(statement, column: 5, name: "threads.updated_at")
                records.append(ThreadIndexRecord(
                    threadID: try requiredText(statement, column: 0, name: "threads.id"),
                    rolloutPath: try requiredText(statement, column: 1, name: "threads.rollout_path"),
                    sourceRaw: try requiredText(statement, column: 2, name: "threads.source"),
                    model: try optionalText(statement, column: 3, name: "threads.model"),
                    createdAtMilliseconds: try milliseconds(created, alreadyMilliseconds: createdAtIsMilliseconds),
                    updatedAtMilliseconds: try milliseconds(updated, alreadyMilliseconds: updatedAtIsMilliseconds),
                    archived: try requiredBoolean(statement, column: 6, name: "threads.archived"),
                    childEdgeStatus: nil
                ))
            case SQLITE_DONE:
                return records
            case let code:
                throw CodexThreadIndexError.queryFailed(code, context: "read threads")
            }
        }
    }

    private func readEdgeStatuses(
        database: OpaquePointer,
        knownThreadIDs: Set<String>
    ) throws -> [String: String] {
        let sql = "SELECT child_thread_id, status FROM thread_spawn_edges ORDER BY child_thread_id"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CodexThreadIndexError.queryFailed(prepareResult, context: "read thread edges")
        }
        defer { sqlite3_finalize(statement) }

        var statuses: [String: String] = [:]
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let threadID = try requiredText(
                    statement,
                    column: 0,
                    name: "thread_spawn_edges.child_thread_id"
                )
                guard knownThreadIDs.contains(threadID) else { continue }
                guard let status = try optionalText(
                    statement,
                    column: 1,
                    name: "thread_spawn_edges.status"
                ) else { continue }
                if let existing = statuses[threadID], existing != status {
                    throw CodexThreadIndexError.conflictingChildStatuses
                }
                statuses[threadID] = status
            case SQLITE_DONE:
                return statuses
            case let code:
                throw CodexThreadIndexError.queryFailed(code, context: "read thread edges")
            }
        }
    }

    private func requiredText(_ statement: OpaquePointer, column: Int32, name: String) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else {
            throw CodexThreadIndexError.invalidValue(name)
        }
        return String(cString: pointer)
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32, name: String) throws -> String? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return nil }
        return try requiredText(statement, column: column, name: name)
    }

    private func requiredInteger(_ statement: OpaquePointer, column: Int32, name: String) throws -> Int64 {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else {
            throw CodexThreadIndexError.invalidValue(name)
        }
        return sqlite3_column_int64(statement, column)
    }

    private func requiredBoolean(_ statement: OpaquePointer, column: Int32, name: String) throws -> Bool {
        let value = try requiredInteger(statement, column: column, name: name)
        guard value == 0 || value == 1 else {
            throw CodexThreadIndexError.invalidValue(name)
        }
        return value == 1
    }

    private func milliseconds(_ value: Int64, alreadyMilliseconds: Bool) throws -> Int64 {
        guard !alreadyMilliseconds else { return value }
        let (result, overflow) = value.multipliedReportingOverflow(by: 1_000)
        guard !overflow else { throw CodexThreadIndexError.timestampOverflow }
        return result
    }
}

enum CodexThreadIndexError: Error, CustomStringConvertible, Equatable {
    case openFailed(Int32)
    case busyTimeoutFailed(Int32)
    case missingTable(String)
    case missingColumns(table: String, columns: [String])
    case queryFailed(Int32, context: String)
    case invalidValue(String)
    case timestampOverflow
    case conflictingChildStatuses

    var description: String {
        switch self {
        case .openFailed:
            return "index open failed"
        case .busyTimeoutFailed:
            return "index busy timeout setup failed"
        case let .missingTable(table):
            return "missing table: \(table)"
        case let .missingColumns(table, columns):
            return "missing columns in \(table): \(columns.joined(separator: ","))"
        case let .queryFailed(_, context):
            return "index query failed: \(context)"
        case let .invalidValue(column):
            return "invalid index value: \(column)"
        case .timestampOverflow:
            return "index timestamp overflow"
        case .conflictingChildStatuses:
            return "conflicting child edge statuses"
        }
    }
}
