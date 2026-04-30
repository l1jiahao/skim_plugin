import CSQLite
import Foundation

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Could not open SQLite database: \(message)"
        case .prepareFailed(let message):
            return "Could not prepare SQLite statement: \(message)"
        case .stepFailed(let message):
            return "SQLite statement failed: \(message)"
        case .bindFailed(let message):
            return "Could not bind SQLite value: \(message)"
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        FileManager.default.createDirectoryIfNeeded(at: url.deletingLastPathComponent())
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw SQLiteError.openFailed(lastErrorMessage)
        }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        sqlite3_close(db)
    }

    var lastErrorMessage: String {
        guard let db else { return "unknown database error" }
        return String(cString: sqlite3_errmsg(db))
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorPointer) != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorPointer)
            throw SQLiteError.stepFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }
        guard let statement else {
            throw SQLiteError.prepareFailed("sqlite3_prepare_v2 returned nil")
        }
        return statement
    }

    func stepToDone(_ statement: OpaquePointer) throws {
        if sqlite3_step(statement) != SQLITE_DONE {
            throw SQLiteError.stepFailed(lastErrorMessage)
        }
    }

    func bind(_ string: String?, at index: Int32, in statement: OpaquePointer) throws {
        let result: Int32
        if let string {
            result = sqlite3_bind_text(statement, index, string, -1, transientDestructor)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        if result != SQLITE_OK {
            throw SQLiteError.bindFailed(lastErrorMessage)
        }
    }

    func bind(_ int: Int, at index: Int32, in statement: OpaquePointer) throws {
        if sqlite3_bind_int64(statement, index, sqlite3_int64(int)) != SQLITE_OK {
            throw SQLiteError.bindFailed(lastErrorMessage)
        }
    }

    func bind(_ double: Double, at index: Int32, in statement: OpaquePointer) throws {
        if sqlite3_bind_double(statement, index, double) != SQLITE_OK {
            throw SQLiteError.bindFailed(lastErrorMessage)
        }
    }
}

extension FileManager {
    func createDirectoryIfNeeded(at url: URL) {
        guard !fileExists(atPath: url.path) else { return }
        try? createDirectory(at: url, withIntermediateDirectories: true)
    }
}

