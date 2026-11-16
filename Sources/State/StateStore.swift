import SQLite3
import Foundation

/// A synced photo's state: links an album asset to a Skylight message.
public struct PhotoRecord: Sendable, Equatable {
    public var assetID: String
    public var messageID: String
    public var pending: Bool

    public init(assetID: String, messageID: String, pending: Bool) {
        self.assetID = assetID
        self.messageID = messageID
        self.pending = pending
    }
}

/// SQLite state store mapping photo asset IDs to Skylight message IDs.
public final class StateStore: Sendable {
    private let db: DatabaseHandle

    /// Opens (or creates) the database at `path`. Use `:memory:` for tests.
    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw StateError.open(msg)
        }
        self.db = DatabaseHandle(handle)

        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA busy_timeout=5000")
        try exec("""
            CREATE TABLE IF NOT EXISTS photo (
                asset_id  TEXT PRIMARY KEY NOT NULL,
                message_id TEXT NOT NULL,
                pending   INTEGER NOT NULL DEFAULT 0
            )
            """)
    }

    /// Insert a new record.
    public func insert(assetID: String, messageID: String, pending: Bool) throws {
        try exec(
            "INSERT OR REPLACE INTO photo (asset_id, message_id, pending) VALUES (?, ?, ?)",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, assetID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, messageID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 3, pending ? 1 : 0)
            }
        )
    }

    /// Mark a record as no longer pending (upload confirmed).
    public func clearPending(assetID: String) throws {
        try exec(
            "UPDATE photo SET pending = 0 WHERE asset_id = ?",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, assetID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        )
    }

    /// Delete a single record by asset ID.
    public func delete(assetID: String) throws {
        try exec(
            "DELETE FROM photo WHERE asset_id = ?",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, assetID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        )
    }

    /// Delete multiple records by asset ID.
    public func deleteAll(assetIDs: [String]) throws {
        guard !assetIDs.isEmpty else { return }
        let placeholders = assetIDs.map { _ in "?" }.joined(separator: ",")
        try exec(
            "DELETE FROM photo WHERE asset_id IN (\(placeholders))",
            bind: { stmt in
                for (i, id) in assetIDs.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
        )
    }

    /// Returns all records.
    public func listAll() throws -> [PhotoRecord] {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db.ptr, "SELECT asset_id, message_id, pending FROM photo", -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw StateError.query(String(cString: sqlite3_errmsg(db.ptr)))
        }
        defer { sqlite3_finalize(stmt) }

        var records: [PhotoRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let assetID = String(cString: sqlite3_column_text(stmt, 0))
            let messageID = String(cString: sqlite3_column_text(stmt, 1))
            let pending = sqlite3_column_int(stmt, 2) != 0
            records.append(PhotoRecord(assetID: assetID, messageID: messageID, pending: pending))
        }
        return records
    }

    /// Returns the current journal mode (e.g. "wal").
    public func journalMode() throws -> String {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db.ptr, "PRAGMA journal_mode", -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw StateError.query(String(cString: sqlite3_errmsg(db.ptr)))
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    /// Closes the database.
    public func close() {
        sqlite3_close(db.ptr)
    }

    // MARK: - Private

    private func exec(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws {
        if bind == nil {
            // Simple exec for DDL/pragma
            let rc = sqlite3_exec(db.ptr, sql, nil, nil, nil)
            guard rc == SQLITE_OK else {
                throw StateError.query(String(cString: sqlite3_errmsg(db.ptr)))
            }
            return
        }

        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db.ptr, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else {
            throw StateError.query(String(cString: sqlite3_errmsg(db.ptr)))
        }
        defer { sqlite3_finalize(stmt) }
        bind?(stmt!)
        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE || stepRC == SQLITE_ROW else {
            throw StateError.query(String(cString: sqlite3_errmsg(db.ptr)))
        }
    }
}

/// Wraps an OpaquePointer for Sendable conformance.
/// The database is opened with SQLITE_OPEN_FULLMUTEX so concurrent access is safe.
private final class DatabaseHandle: @unchecked Sendable {
    let ptr: OpaquePointer
    init(_ ptr: OpaquePointer) { self.ptr = ptr }
}

public enum StateError: Error, LocalizedError {
    case open(String)
    case query(String)

    public var errorDescription: String? {
        switch self {
        case .open(let msg): "failed to open state database: \(msg)"
        case .query(let msg): "state database error: \(msg)"
        }
    }
}
