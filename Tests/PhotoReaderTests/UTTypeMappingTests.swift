import XCTest
@testable import PhotoReader

final class UTTypeMappingTests: XCTestCase {
    func testJPEG() {
        XCTAssertEqual(extensionForUTType("public.jpeg"), "jpg")
    }

    func testHEIC() {
        XCTAssertEqual(extensionForUTType("public.heic"), "heic")
    }

    func testPNG() {
        XCTAssertEqual(extensionForUTType("public.png"), "png")
    }

    func testHEIF() {
        XCTAssertEqual(extensionForUTType("public.heif"), "heic")
    }

    func testUnknown() {
        XCTAssertEqual(extensionForUTType("public.tiff"), "jpg")
    }

    func testGIF() {
        XCTAssertEqual(extensionForUTType("public.gif"), "gif")
    }

    func testWebP() {
        XCTAssertEqual(extensionForUTType("public.webp"), "webp")
    }
}
