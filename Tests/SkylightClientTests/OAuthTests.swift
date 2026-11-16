import XCTest
@testable import SkylightClient

final class OAuthTests: XCTestCase {
    func testPKCEGeneratesValidVerifierAndChallenge() throws {
        let pkce = try SkylightAuth.PKCE.generate()
        XCTAssertEqual(pkce.verifier.count, 86) // 64 bytes base64url = 86 chars
        XCTAssertFalse(pkce.challenge.isEmpty)
        XCTAssertNotEqual(pkce.verifier, pkce.challenge)
    }

    func testPKCEIsDeterministicForSameVerifier() throws {
        // Two calls produce different verifiers (random).
        let a = try SkylightAuth.PKCE.generate()
        let b = try SkylightAuth.PKCE.generate()
        XCTAssertNotEqual(a.verifier, b.verifier)
    }

    func testAuthorizeURLContainsRequiredParams() {
        let url = SkylightAuth.authorizeURL(challenge: "test_challenge")
        let s = url.absoluteString
        XCTAssertTrue(s.contains("client_id=skylight-mobile"))
        XCTAssertTrue(s.contains("code_challenge=test_challenge"))
        XCTAssertTrue(s.contains("code_challenge_method=S256"))
        XCTAssertTrue(s.contains("response_type=code"))
        XCTAssertTrue(s.contains("scope=everything"))
        XCTAssertTrue(s.contains("prompt=login"))
        XCTAssertTrue(s.hasPrefix("https://app.ourskylight.com/oauth/authorize?"))
    }

    func testExtractCodeFromRedirectURL() throws {
        let code = try SkylightAuth.extractCode(from: "https://ourskylight.com/welcome?code=abc123")
        XCTAssertEqual(code, "abc123")
    }

    func testExtractCodeFromBareCode() throws {
        let code = try SkylightAuth.extractCode(from: "abc123")
        XCTAssertEqual(code, "abc123")
    }

    func testExtractCodeFromCodePrefix() throws {
        let code = try SkylightAuth.extractCode(from: "code=abc123")
        XCTAssertEqual(code, "abc123")
    }

    func testExtractCodeTrimsWhitespace() throws {
        let code = try SkylightAuth.extractCode(from: "  abc123  \n")
        XCTAssertEqual(code, "abc123")
    }

    func testExtractCodeThrowsOnEmpty() {
        XCTAssertThrowsError(try SkylightAuth.extractCode(from: ""))
        XCTAssertThrowsError(try SkylightAuth.extractCode(from: "  "))
    }

    func testExtractCodeThrowsOnURLWithoutCode() {
        XCTAssertThrowsError(try SkylightAuth.extractCode(from: "https://example.com/callback"))
    }

    func testNewFingerprintIsHex32() throws {
        let fp = try SkylightAuth.newFingerprint()
        XCTAssertEqual(fp.count, 32) // 16 bytes hex
        XCTAssertTrue(fp.allSatisfy { $0.isHexDigit })
    }
}
