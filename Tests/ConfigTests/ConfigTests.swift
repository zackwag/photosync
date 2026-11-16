import XCTest
@testable import Config

final class ConfigTests: XCTestCase {
    func testRoundTrip() throws {
        let config = SyncConfig(albumID: "A", albumTitle: "B", frameID: "1", frameName: "F", pollInterval: 120)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SyncConfig.self, from: data)
        XCTAssertEqual(decoded.albumID, "A")
        XCTAssertEqual(decoded.albumTitle, "B")
        XCTAssertEqual(decoded.frameID, "1")
        XCTAssertEqual(decoded.frameName, "F")
        XCTAssertEqual(decoded.pollInterval, 120)
    }

    func testDefaultPollInterval() throws {
        let json = #"{"album_id":"A","album_title":"B","frame_id":"1","frame_name":"F"}"#
        let config = try JSONDecoder().decode(SyncConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.pollInterval, 300)
    }

    func testPathsUnderApplicationSupport() {
        XCTAssertTrue(Paths.configURL.path.contains("PhotoSync/config.json"))
        XCTAssertTrue(Paths.stateURL.path.contains("PhotoSync/state.db"))
    }

    func testLogPathUnderLogs() {
        XCTAssertTrue(Paths.logURL.path.contains("Logs/PhotoSync/daemon.log"))
    }

    func testSaveAndLoad() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let config = SyncConfig(albumID: "X", albumTitle: "Y", frameID: "9", frameName: "Z", pollInterval: 60)
        try SyncConfig.save(config, to: tmp)
        let loaded = try SyncConfig.load(from: tmp)
        XCTAssertEqual(loaded, config)
    }
}
