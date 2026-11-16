import XCTest
import os
@testable import SkylightClient

final class ClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
    }

    func testAutoRefreshOn401() async throws {
        let refreshCalled = OSAllocatedUnfairLock(initialState: false)

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString

            // Token refresh request
            if url.contains("/oauth/token") {
                let tokenJSON = #"{"access_token":"new_access","refresh_token":"new_refresh"}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(tokenJSON.utf8))
            }

            // First API call returns 401, second returns 200
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old_access" {
                return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                        Data())
            }

            // After refresh, return frames
            let framesJSON = #"{"data":[{"id":"1","type":"frame","attributes":{"name":"test","household_name":"Home"}}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(framesJSON.utf8))
        }

        let client = SkylightClient(
            token: Token(accessToken: "old_access", refreshToken: "old_refresh"),
            fingerprint: "fp",
            session: MockURLProtocol.mockSession(),
            onRefresh: { _ in refreshCalled.withLock { $0 = true } }
        )

        let frames = try await client.frames()
        XCTAssertTrue(refreshCalled.withLock { $0 })
        XCTAssertEqual(frames.first?.name, "Home")
        XCTAssertEqual(client.currentToken().accessToken, "new_access")
    }

    func testThrowsAPIErrorOn4xx() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!,
             Data(#"{"errors":["bad"]}"#.utf8))
        }

        let client = SkylightClient(
            token: Token(accessToken: "tok", refreshToken: "ref"),
            fingerprint: "fp",
            session: MockURLProtocol.mockSession()
        )

        do {
            _ = try await client.frames()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 422)
            XCTAssertTrue(error.body.contains("bad"))
        }
    }

    func testFramesPrefersHouseholdName() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"data":[{"id":"42","type":"frame","attributes":{"name":"slug","household_name":"My House"}}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(json.utf8))
        }

        let client = SkylightClient(
            token: Token(accessToken: "tok", refreshToken: "ref"),
            fingerprint: "fp",
            session: MockURLProtocol.mockSession()
        )
        let frames = try await client.frames()
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].id, "42")
        XCTAssertEqual(frames[0].name, "My House")
    }

    func testFramesFallsBackToName() async throws {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"data":[{"id":"42","type":"frame","attributes":{"name":"slug","household_name":""}}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(json.utf8))
        }

        let client = SkylightClient(
            token: Token(accessToken: "tok", refreshToken: "ref"),
            fingerprint: "fp",
            session: MockURLProtocol.mockSession()
        )
        let frames = try await client.frames()
        XCTAssertEqual(frames[0].name, "slug")
    }
}
