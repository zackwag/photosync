import Foundation

/// OAuth access/refresh token pair.
public struct Token: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

/// A Skylight household (one physical frame).
public struct Frame: Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Result of uploading a photo to Skylight.
public struct UploadResult: Sendable {
    public var presignedURL: URL
    public var messageID: String
    public var s3Key: String

    public init(presignedURL: URL, messageID: String, s3Key: String) {
        self.presignedURL = presignedURL
        self.messageID = messageID
        self.s3Key = s3Key
    }
}

/// A non-2xx response from the Skylight API.
public struct APIError: Error, LocalizedError, Sendable {
    public var method: String
    public var path: String
    public var statusCode: Int
    public var body: String

    public init(method: String, path: String, statusCode: Int, body: String) {
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.body = body
    }

    public var errorDescription: String? {
        "skylight: \(method) \(path) returned \(statusCode): \(body)"
    }
}
