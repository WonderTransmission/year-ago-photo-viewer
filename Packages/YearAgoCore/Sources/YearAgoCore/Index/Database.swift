import Foundation
import SQLite3

/// An error from SQLite, with its message.
public struct DatabaseError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// A value bound to a statement parameter.
enum SQLValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null

    static func optionalInt<T: BinaryInteger>(_ value: T?) -> SQLValue {
        value.map { .int(Int64($0)) } ?? .null
    }

    static func date(_ value: LocalDateTime?) -> SQLValue {
        value.map { .int($0.seconds) } ?? .null
    }
}

/// A minimal wrapper over a SQLite connection.
///
/// Not thread-safe and not `Sendable`. `PhotoIndex`, an actor, owns the only
/// instance and serializes all access.
final class Database {
    private var handle: OpaquePointer?

    /// Opens or creates the database at `path`. Pass ":memory:" for a
    /// private in-memory database.
    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            let error = DatabaseError(code: status, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed")
            sqlite3_close(handle)
            throw error
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that return no rows.
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if status != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw DatabaseError(code: status, message: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else { throw lastError(status) }
        return Statement(handle: statement, database: self)
    }

    /// Runs `body` in a transaction. Rolls back if it throws.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// The schema version stored in the file.
    var userVersion: Int {
        get throws {
            let statement = try prepare("PRAGMA user_version")
            _ = try statement.step()
            return Int(statement.int64(0))
        }
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    /// Rows changed by the most recent INSERT, UPDATE, or DELETE.
    var changes: Int { Int(sqlite3_changes(handle)) }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    fileprivate func lastError(_ status: Int32) -> DatabaseError {
        DatabaseError(code: status, message: String(cString: sqlite3_errmsg(handle)))
    }
}

/// A prepared statement. Reuse it with `reset()` and new bindings.
final class Statement {
    private let handle: OpaquePointer
    private let database: Database

    fileprivate init(handle: OpaquePointer, database: Database) {
        self.handle = handle
        self.database = database
    }

    deinit {
        sqlite3_finalize(handle)
    }

    /// Binds values to parameters 1, 2, 3, … in order.
    @discardableResult
    func bind(_ values: [SQLValue]) throws -> Statement {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .int(let v): status = sqlite3_bind_int64(handle, index, v)
            case .double(let v): status = sqlite3_bind_double(handle, index, v)
            case .text(let v): status = sqlite3_bind_text(handle, index, v, -1, sqliteTransient)
            case .blob(let v):
                status = v.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(handle, index, bytes.baseAddress, Int32(v.count), sqliteTransient)
                }
            case .null: status = sqlite3_bind_null(handle, index)
            }
            guard status == SQLITE_OK else { throw database.lastError(status) }
        }
        return self
    }

    /// Advances to the next row. Returns false when there are no more rows.
    func step() throws -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case let status: throw database.lastError(status)
        }
    }

    /// Runs a statement that returns no rows.
    func run(_ values: [SQLValue] = []) throws {
        try bind(values)
        while try step() {}
    }

    func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    func optionalInt64(_ column: Int32) -> Int64? {
        isNull(column) ? nil : int64(column)
    }

    func blob(_ column: Int32) -> Data? {
        guard !isNull(column) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        guard count > 0, let bytes = sqlite3_column_blob(handle, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    func text(_ column: Int32) -> String {
        sqlite3_column_text(handle, column).map { String(cString: $0) } ?? ""
    }
}

/// SQLite's SQLITE_TRANSIENT, which Swift does not import: tells SQLite to
/// copy bound text and blobs.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
