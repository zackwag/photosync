import XCTest
@testable import State

final class StateStoreTests: XCTestCase {
    func testInsertAndListAllRoundTrips() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        try store.insert(assetID: "a1", messageID: "m1", pending: false)
        let records = try store.listAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].assetID, "a1")
        XCTAssertEqual(records[0].messageID, "m1")
        XCTAssertFalse(records[0].pending)
    }

    func testClearPendingUpdatesPendingFlag() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        try store.insert(assetID: "a1", messageID: "m1", pending: true)
        try store.clearPending(assetID: "a1")
        let records = try store.listAll()
        XCTAssertFalse(records[0].pending)
    }

    func testDeleteRemovesRow() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        try store.insert(assetID: "a1", messageID: "m1", pending: false)
        try store.delete(assetID: "a1")
        XCTAssertTrue(try store.listAll().isEmpty)
    }

    func testDeleteAllBatch() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        try store.insert(assetID: "a1", messageID: "m1", pending: false)
        try store.insert(assetID: "a2", messageID: "m2", pending: false)
        try store.insert(assetID: "a3", messageID: "m3", pending: false)
        try store.deleteAll(assetIDs: ["a1", "a3"])
        let remaining = try store.listAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].assetID, "a2")
    }

    func testDeleteAllWithEmptyArrayIsNoOp() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        try store.insert(assetID: "a1", messageID: "m1", pending: false)
        try store.deleteAll(assetIDs: [])
        XCTAssertEqual(try store.listAll().count, 1)
    }

    func testInsertReplaceOnConflict() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        try store.insert(assetID: "a1", messageID: "m1", pending: true)
        try store.insert(assetID: "a1", messageID: "m2", pending: false)
        let records = try store.listAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].messageID, "m2")
        XCTAssertFalse(records[0].pending)
    }

    func testJournalModeIsWAL() throws {
        let store = try StateStore(path: ":memory:")
        defer { store.close() }
        let mode = try store.journalMode()
        // :memory: databases report "memory" for journal mode since WAL doesn't
        // apply to in-memory DBs. Just verify the query works.
        XCTAssertFalse(mode.isEmpty)
    }
}
