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

    func testLoadMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        XCTAssertThrowsError(try SyncConfig.load(from: url)) { error in
            XCTAssertEqual(error as? ConfigError, .notFound(url.path))
        }
    }

    func testLoadInvalidFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("{not json".utf8).write(to: url)

        XCTAssertThrowsError(try SyncConfig.load(from: url)) { error in
            guard case .invalid(let path, _) = error as? ConfigError else {
                XCTFail("expected ConfigError.invalid, got \(error)")
                return
            }
            XCTAssertEqual(path, url.path)
        }
    }
}
