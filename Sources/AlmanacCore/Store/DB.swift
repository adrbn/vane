import Foundation
import SQLite3

public enum DBError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let m) = self { return "Database: \(m)" }; return nil }
}

public struct Row {
    let values: [Any?]
    public func s(_ i: Int) -> String { values[i] as? String ?? "" }
    public func d(_ i: Int) -> Double { (values[i] as? Double) ?? Double(values[i] as? Int64 ?? 0) }
    public func i(_ i: Int) -> Int { Int(values[i] as? Int64 ?? Int64(values[i] as? Double ?? 0)) }
    public func opt(_ i: Int) -> String? { values[i] as? String }
}

/// Minimal SQLite wrapper. One connection per process side; WAL lets the
/// background agent write while the app reads.
public final class DB: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else { throw DBError.sqlite("cannot open \(path)") }
        sqlite3_busy_timeout(handle, 5000)
        try exec("PRAGMA journal_mode=WAL")
    }

    deinit { sqlite3_close(handle) }

    public func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError.sqlite(msg)
        }
    }

    @discardableResult
    public func query(_ sql: String, _ args: [Any?] = []) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, DB.transient)
            default: sqlite3_bind_text(stmt, idx, "\(a!)", -1, DB.transient)
            }
        }
        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DBError.sqlite(String(cString: sqlite3_errmsg(handle))) }
            let n = sqlite3_column_count(stmt)
            var vals: [Any?] = []
            for c in 0..<n {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: vals.append(sqlite3_column_int64(stmt, c))
                case SQLITE_FLOAT: vals.append(sqlite3_column_double(stmt, c))
                case SQLITE_TEXT: vals.append(String(cString: sqlite3_column_text(stmt, c)))
                default: vals.append(nil)
                }
            }
            rows.append(Row(values: vals))
        }
        return rows
    }

    /// Bulk insert with one prepared statement (100× faster than `query` per row).
    public func insertMany(_ sql: String, _ rows: [[Any?]]) throws {
        try transaction {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw DBError.sqlite(String(cString: sqlite3_errmsg(handle))) }
            defer { sqlite3_finalize(stmt) }
            for row in rows {
                sqlite3_reset(stmt)
                for (i, a) in row.enumerated() {
                    let idx = Int32(i + 1)
                    switch a {
                    case let v as Double: sqlite3_bind_double(stmt, idx, v)
                    case let v as String: sqlite3_bind_text(stmt, idx, v, -1, DB.transient)
                    default: sqlite3_bind_null(stmt, idx)
                    }
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw DBError.sqlite(String(cString: sqlite3_errmsg(handle))) }
            }
        }
    }

    public func transaction(_ body: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN")
        do { try body(); try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }
}
