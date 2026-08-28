import Foundation
import SQLite3

public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    public init(path: String, readOnly: Bool) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &handle, flags, nil)
        guard status == SQLITE_OK, handle != nil else {
            throw PubMergeError.sqliteFailure(lastError())
        }
        if !readOnly {
            try execute("PRAGMA journal_mode=DELETE;")
            try execute("PRAGMA foreign_keys=ON;")
        }
    }

    deinit {
        if handle != nil {
            sqlite3_close(handle)
        }
    }

    public func close() {
        if handle != nil {
            sqlite3_close(handle)
            handle = nil
        }
    }

    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &error)
        if let error {
            let message = String(cString: error)
            sqlite3_free(error)
            if status != SQLITE_OK {
                throw PubMergeError.sqliteFailure(message)
            }
        } else if status != SQLITE_OK {
            throw PubMergeError.sqliteFailure(lastError())
        }
    }

    public func scalarInt(_ sql: String) throws -> Int {
        let rows = try query(sql)
        if let value = rows.first?.values.first {
            return value.intValue ?? 0
        }
        return 0
    }

    public func scalarString(_ sql: String) throws -> String? {
        let rows = try query(sql)
        return rows.first?.values.first?.textValue
    }

    public func tableExists(_ name: String) throws -> Bool {
        let escaped = name.replacingOccurrences(of: "'", with: "''")
        return try scalarInt("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='\(escaped)'") > 0
    }

    public func columns(of table: String) throws -> Set<String> {
        let rows = try query("PRAGMA table_info(\(table));")
        return Set(rows.compactMap { $0["name"]?.textValue })
    }

    public func userVersion() throws -> Int {
        try scalarInt("PRAGMA user_version;")
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version=\(version);")
    }

    public func journalMode() throws -> String {
        try scalarString("PRAGMA journal_mode;") ?? "delete"
    }

    public func foreignKeyViolations() throws -> [String] {
        let rows = try query("PRAGMA foreign_key_check;")
        return rows.map { row in
            let table = row["table"]?.textValue ?? "?"
            let rowid = row["rowid"]?.intValue ?? 0
            let parent = row["parent"]?.textValue ?? "?"
            return "\(table)#\(rowid) -> \(parent)"
        }
    }

    @discardableResult
    public func query(_ sql: String, binds: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PubMergeError.sqliteFailure(lastError())
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in binds.enumerated() {
            try bind(value, at: Int32(index + 1), statement: statement)
        }

        let columnCount = sqlite3_column_count(statement)
        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for index in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = columnValue(statement, index)
            }
            rows.append(row)
        }
        return rows
    }

    public func insert(_ sql: String, binds: [SQLiteValue]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PubMergeError.sqliteFailure(lastError())
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in binds.enumerated() {
            try bind(value, at: Int32(index + 1), statement: statement)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PubMergeError.sqliteFailure(lastError())
        }
    }

    private func bind(_ value: SQLiteValue, at index: Int32, statement: OpaquePointer) throws {
        let status: Int32
        switch value {
        case .null:
            status = sqlite3_bind_null(statement, index)
        case .int(let number):
            status = sqlite3_bind_int64(statement, index, Int64(number))
        case .text(let text):
            status = sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard status == SQLITE_OK else {
            throw PubMergeError.sqliteFailure(lastError())
        }
    }

    private func columnValue(_ statement: OpaquePointer, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .int(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_TEXT:
            if let pointer = sqlite3_column_text(statement, index) {
                return .text(String(cString: pointer))
            }
            return .null
        default:
            return .null
        }
    }

    private func lastError() -> String {
        if let handle {
            return String(cString: sqlite3_errmsg(handle))
        }
        return "Unknown SQLite error"
    }
}

public enum SQLiteValue: Equatable, Sendable {
    case null
    case int(Int)
    case text(String)

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .text(let value): return Int(value)
        case .null: return nil
        }
    }

    public var textValue: String? {
        switch self {
        case .text(let value): return value
        case .int(let value): return String(value)
        case .null: return nil
        }
    }

    public static func optional(_ value: Int?) -> SQLiteValue {
        value.map(SQLiteValue.int) ?? .null
    }

    public static func optional(_ value: String?) -> SQLiteValue {
        value.map(SQLiteValue.text) ?? .null
    }
}
