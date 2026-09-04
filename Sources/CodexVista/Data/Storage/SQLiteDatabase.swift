import Foundation
import SQLite3

enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    var int64: Int64? {
        guard case let .integer(value) = self else { return nil }
        return value
    }

    var string: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }
}

struct SQLiteDatabaseError: Error, CustomStringConvertible, Equatable {
    let code: Int32
    let message: String
    let sql: String?

    var description: String {
        if let sql {
            return "SQLite error \(code): \(message) [\(sql)]"
        }
        return "SQLite error \(code): \(message)"
    }
}

final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)

        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unable to allocate SQLite database handle"
            if let database {
                sqlite3_close_v2(database)
            }
            throw SQLiteDatabaseError(code: result, message: message, sql: nil)
        }

        handle = database
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    @discardableResult
    func execute(sql: String, bindings: [SQLiteValue] = []) throws -> Int32 {
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement, sql: sql)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw error(code: result, sql: sql)
        }
        return sqlite3_changes(handle)
    }

    func query(sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement, sql: sql)
        var rows: [[String: SQLiteValue]] = []

        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                var row: [String: SQLiteValue] = [:]
                for column in 0..<sqlite3_column_count(statement) {
                    guard let namePointer = sqlite3_column_name(statement, column) else { continue }
                    row[String(cString: namePointer)] = value(statement: statement, column: column)
                }
                rows.append(row)
            case SQLITE_DONE:
                return rows
            default:
                throw error(code: result, sql: sql)
            }
        }
    }

    func inTransaction<T>(_ operation: () throws -> T) throws -> T {
        try execute(sql: "BEGIN IMMEDIATE")
        do {
            let result = try operation()
            try execute(sql: "COMMIT")
            return result
        } catch {
            _ = try? execute(sql: "ROLLBACK")
            throw error
        }
    }

    private func prepare(sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw error(code: result, sql: sql)
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer, sql: String) throws {
        let expectedCount = Int(sqlite3_bind_parameter_count(statement))
        guard expectedCount == bindings.count else {
            throw SQLiteDatabaseError(
                code: SQLITE_MISUSE,
                message: "Expected \(expectedCount) bindings, received \(bindings.count)",
                sql: sql
            )
        }

        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32

            switch binding {
            case let .integer(value):
                result = sqlite3_bind_int64(statement, index, value)
            case let .real(value):
                result = sqlite3_bind_double(statement, index, value)
            case let .text(value):
                result = value.withCString { pointer in
                    sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
                }
            case .null:
                result = sqlite3_bind_null(statement, index)
            }

            guard result == SQLITE_OK else {
                throw error(code: result, sql: sql)
            }
        }
    }

    private func value(statement: OpaquePointer, column: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, column) else { return .null }
            return .text(String(cString: pointer))
        default:
            return .null
        }
    }

    private func error(code: Int32, sql: String?) -> SQLiteDatabaseError {
        SQLiteDatabaseError(code: code, message: String(cString: sqlite3_errmsg(handle)), sql: sql)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
