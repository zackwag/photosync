#if canImport(Photos)
import Photos
import XCTest
@testable import PhotoReader

final class AccessTests: XCTestCase {
    func testValidate() {
        let cases: [(status: PHAuthorizationStatus, expected: PhotoReaderError?)] = [
            (.authorized, nil),
            (.limited, .accessLimited),
            (.notDetermined, .accessNotDetermined),
            (.denied, .accessDenied),
            (.restricted, .accessDenied),
        ]
        for c in cases {
            do {
                try PhotoKitReader.validate(c.status)
                XCTAssertNil(c.expected, "status \(c.status.rawValue) should throw")
            } catch let error as PhotoReaderError {
                XCTAssertEqual(error, c.expected, "status \(c.status.rawValue)")
            } catch {
                XCTFail("unexpected error \(error)")
            }
        }
    }

    func testIsAccessError() {
        XCTAssertTrue(PhotoReaderError.accessDenied.isAccessError)
        XCTAssertTrue(PhotoReaderError.accessLimited.isAccessError)
        XCTAssertTrue(PhotoReaderError.accessNotDetermined.isAccessError)
        XCTAssertFalse(PhotoReaderError.albumNotFound("x").isAccessError)
        XCTAssertFalse(PhotoReaderError.assetNotFound("x").isAccessError)
        XCTAssertFalse(PhotoReaderError.exportFailed("x").isAccessError)
    }
}
#endif
