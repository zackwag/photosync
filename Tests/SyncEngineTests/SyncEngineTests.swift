import XCTest
@testable import SyncEngine
import State

final class SyncEngineTests: XCTestCase {
    func testEmptyBothSidesProducesNoPlan() {
        let plan = SyncEngine.plan(albumAssetIDs: [], stateRecords: [], force: false)
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testNewAssetsAreUploads() {
        let plan = SyncEngine.plan(albumAssetIDs: ["a", "b"], stateRecords: [], force: false)
        XCTAssertEqual(Set(plan.uploads), ["a", "b"])
    }

    func testRemovedAssetsAreDeletes() {
        let records = [PhotoRecord(assetID: "a", messageID: "m1", pending: false)]
        let plan = SyncEngine.plan(albumAssetIDs: [], stateRecords: records, force: false)
        XCTAssertEqual(plan.deletes.count, 1)
        XCTAssertEqual(plan.deletes[0].messageID, "m1")
    }

    func testPresentInBothIsNoAction() {
        let records = [PhotoRecord(assetID: "a", messageID: "m1", pending: false)]
        let plan = SyncEngine.plan(albumAssetIDs: ["a"], stateRecords: records, force: false)
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testPendingRecordsAreReUploads() {
        let records = [PhotoRecord(assetID: "a", messageID: "m1", pending: true)]
        let plan = SyncEngine.plan(albumAssetIDs: ["a"], stateRecords: records, force: false)
        XCTAssertEqual(plan.uploads, ["a"])
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testMassDeleteThreshold() {
        // max(5, 25% of 100) = 25. Deleting 26 should exceed.
        XCTAssertTrue(SyncEngine.massDeleteExceeded(deleteCount: 26, totalLinked: 100))
        XCTAssertFalse(SyncEngine.massDeleteExceeded(deleteCount: 25, totalLinked: 100))
        // Small set: max(5, 25% of 8) = 5. Deleting 6 exceeds.
        XCTAssertTrue(SyncEngine.massDeleteExceeded(deleteCount: 6, totalLinked: 8))
        XCTAssertFalse(SyncEngine.massDeleteExceeded(deleteCount: 5, totalLinked: 8))
    }

    func testMixedScenario() {
        let records = [
            PhotoRecord(assetID: "keep", messageID: "m1", pending: false),
            PhotoRecord(assetID: "remove", messageID: "m2", pending: false),
            PhotoRecord(assetID: "retry", messageID: "m3", pending: true),
        ]
        let album: Set<String> = ["keep", "retry", "new"]
        let plan = SyncEngine.plan(albumAssetIDs: album, stateRecords: records, force: false)
        XCTAssertEqual(Set(plan.uploads), ["retry", "new"])
        XCTAssertEqual(plan.deletes.count, 1)
        XCTAssertEqual(plan.deletes[0].assetID, "remove")
    }
}
