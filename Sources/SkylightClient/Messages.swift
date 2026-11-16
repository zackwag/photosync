import Foundation

extension SkylightClient {
    /// Returns all message (photo) IDs on a frame.
    public func messageIDs(frameID: String) async throws -> [String] {
        let data = try await request(method: "GET", path: "/api/frames/\(frameID)/messages/all_ids")
        let doc = try JSONDecoder().decode(IDListDocument.self, from: data)
        return doc.data.map(\.id)
    }

    /// Uploads a photo and returns the result with the Skylight message ID.
    /// Retries once with a fresh presigned URL on S3 403.
    public func upload(frameID: String, ext: String, imageData: Data) async throws -> UploadResult {
        for attempt in 0..<2 {
            let result = try await getUploadURL(frameID: frameID, ext: ext)
            let statusCode = try await putToS3(url: result.presignedURL, data: imageData, ext: ext)
            if statusCode == 403 && attempt == 0 {
                continue // presigned URL expired, get a fresh one
            }
            if statusCode >= 400 {
                throw APIError(method: "PUT", path: result.presignedURL.path, statusCode: statusCode, body: "S3 upload failed")
            }
            return result
        }
        throw APIError(method: "PUT", path: "s3", statusCode: 403, body: "S3 upload failed after retry")
    }

    /// Deletes messages (photos) from a frame.
    public func deleteMessages(frameID: String, ids: [String]) async throws {
        let body = try JSONEncoder().encode(["message_ids": ids])
        _ = try await request(method: "DELETE", path: "/api/frames/\(frameID)/messages/destroy_multiple", body: body)
    }

    // MARK: - Private

    private func getUploadURL(frameID: String, ext: String) async throws -> UploadResult {
        struct UploadRequest: Encodable {
            var ext: String
            var frame_ids: [String]
        }
        let reqBody = try JSONEncoder().encode(UploadRequest(ext: ext, frame_ids: [frameID]))
        let data = try await request(
            method: "POST",
            path: "/api/upload_urls",
            query: [URLQueryItem(name: "request_source", value: "android_share")],
            body: reqBody
        )
        let resp = try JSONDecoder().decode(UploadURLResponse.self, from: data)
        guard let first = resp.data.first, let url = URL(string: first.url) else {
            throw APIError(method: "POST", path: "/api/upload_urls", statusCode: 200, body: "no upload URL returned")
        }
        let messageID = Self.extractMessageID(from: first.url)
        return UploadResult(presignedURL: url, messageID: messageID, s3Key: first.key)
    }

    private func putToS3(url: URL, data: Data, ext: String) async throws -> Int {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.httpBody = data
        req.setValue("image/\(ext)", forHTTPHeaderField: "Content-Type")
        // No auth headers — the presigned URL carries its own auth.
        let (_, response) = try await session.data(for: req)
        return (response as! HTTPURLResponse).statusCode
    }

    /// Extracts the message ID from x-amz-meta-recipient_message_ids in the presigned URL.
    static func extractMessageID(from urlString: String) -> String {
        let marker = "recipient_message_ids="
        guard let range = urlString.range(of: marker) else { return "" }
        let rest = urlString[range.upperBound...]
        if let amp = rest.firstIndex(of: "&") {
            return String(rest[..<amp])
        }
        return String(rest)
    }
}

// MARK: - Response types

private struct IDListDocument: Decodable {
    struct IDResource: Decodable {
        var id: String
    }
    var data: [IDResource]
}

private struct UploadURLResponse: Decodable {
    struct UploadURLData: Decodable {
        var url: String
        var key: String
    }
    var data: [UploadURLData]
}
