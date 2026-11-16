import XCTest
@testable import SkylightClient

final class MessagesTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
    }

    func testMessageIDsParsesJSONAPI() async throws {
        MockURLProtocol.requestHandler = { _ in
            let json = #"{"data":[{"id":"111","type":"id"},{"id":"222","type":"id"}]}"#
            return (HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(json.utf8))
        }

        let client = makeClient()
        let ids = try await client.messageIDs(frameID: "1")
        XCTAssertEqual(ids, ["111", "222"])
    }

    func testUploadParsesMessageIDFromPresignedURL() async throws {
        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("upload_urls") {
                let presigned = "https://s3.amazonaws.com/test.jpg?x-amz-meta-recipient_message_ids=999&X-Amz-Signature=abc"
                let json = """
                {"data":[{"url":"\(presigned)","key":"testkey","get_url":"https://s3/get"}]}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(json.utf8))
            }
            // S3 PUT
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data())
        }

        let client = makeClient()
        let result = try await client.upload(frameID: "1", ext: "jpg", imageData: Data([0xFF]))
        XCTAssertEqual(result.messageID, "999")
        XCTAssertEqual(result.s3Key, "testkey")
    }

    func testDeleteSendsCorrectBody() async throws {
        var capturedBody: Data?

        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "DELETE" {
                capturedBody = request.httpBody
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("[]".utf8))
        }

        let client = makeClient()
        try await client.deleteMessages(frameID: "1", ids: ["111", "222"])

        let parsed = try JSONSerialization.jsonObject(with: capturedBody!) as! [String: [String]]
        XCTAssertEqual(parsed["message_ids"], ["111", "222"])
    }

    func testUploadRetriesOnS3_403() async throws {
        var putCount = 0
        var uploadURLCount = 0

        MockURLProtocol.requestHandler = { request in
            let url = request.url!.absoluteString
            if url.contains("upload_urls") {
                uploadURLCount += 1
                let presigned = "https://s3.amazonaws.com/test.jpg?x-amz-meta-recipient_message_ids=\(uploadURLCount)&X-Amz-Signature=abc"
                let json = """
                {"data":[{"url":"\(presigned)","key":"key\(uploadURLCount)","get_url":"https://s3/get"}]}
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(json.utf8))
            }
            if request.httpMethod == "PUT" {
                putCount += 1
                let status = putCount == 1 ? 403 : 200 // first PUT fails, second succeeds
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                        Data())
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let client = makeClient()
        let result = try await client.upload(frameID: "1", ext: "jpg", imageData: Data([0xFF]))

        XCTAssertEqual(uploadURLCount, 2, "Should have requested a fresh presigned URL")
        XCTAssertEqual(putCount, 2, "Should have retried PUT")
        XCTAssertEqual(result.messageID, "2", "Should use the second presigned URL's message ID")
    }

    func testExtractMessageIDFromURL() {
        let url = "https://s3.amazonaws.com/key.jpg?x-amz-meta-recipient_message_ids=12345&X-Amz-Algo=SHA"
        XCTAssertEqual(SkylightClient.extractMessageID(from: url), "12345")
    }

    func testExtractMessageIDMissing() {
        XCTAssertEqual(SkylightClient.extractMessageID(from: "https://s3.amazonaws.com/key.jpg"), "")
    }

    private func makeClient() -> SkylightClient {
        SkylightClient(
            token: Token(accessToken: "tok", refreshToken: "ref"),
            fingerprint: "fp",
            session: MockURLProtocol.mockSession()
        )
    }
}
