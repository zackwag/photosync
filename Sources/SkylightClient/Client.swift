import Foundation
import os
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authenticated Skylight API client. Refreshes the access token on 401.
public final class SkylightClient: Sendable {
    public static let apiVersion = "2026-05-01"
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    let session: URLSession
    private let fingerprint: String
    private let onRefresh: (@Sendable (Token) -> Void)?

    private let state: OSAllocatedUnfairLock<Token>

    public init(token: Token, fingerprint: String, session: URLSession = .shared, onRefresh: (@Sendable (Token) -> Void)? = nil) {
        self.state = OSAllocatedUnfairLock(initialState: token)
        self.fingerprint = fingerprint
        self.session = session
        self.onRefresh = onRefresh
    }

    /// Current token (may have been refreshed).
    public func currentToken() -> Token {
        state.withLock { $0 }
    }

    /// Send an authenticated API request, auto-refreshing on 401.
    func request(
        method: String, path: String, query: [URLQueryItem]? = nil, body: Data? = nil
    ) async throws -> Data {
        let staleAccess = currentToken().accessToken

        for attempt in 0..<2 {
            let access = attempt == 0 ? staleAccess : currentToken().accessToken
            let (data, statusCode) = try await send(method: method, path: path, query: query, body: body, accessToken: access)

            if statusCode == 401 && attempt == 0 {
                try await refreshToken(staleAccess: staleAccess)
                continue
            }
            if statusCode >= 400 {
                let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
                throw APIError(method: method, path: path, statusCode: statusCode, body: bodyStr)
            }
            return data
        }
        // unreachable, but the compiler needs it
        throw APIError(method: method, path: path, statusCode: 401, body: "still unauthorized after refresh")
    }

    private func send(
        method: String, path: String, query: [URLQueryItem]?, body: Data?, accessToken: String
    ) async throws -> (Data, Int) {
        var components = URLComponents(string: "\(SkylightAuth.baseURL)\(path)")!
        if let query, !query.isEmpty {
            components.queryItems = query
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "Skylight-Api-Version")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: req)
        let httpResp = response as! HTTPURLResponse
        return (data, httpResp.statusCode)
    }

    private func refreshToken(staleAccess: String) async throws {
        let refreshToken: String? = state.withLock { token in
            if token.accessToken != staleAccess {
                return nil // already refreshed by another caller
            }
            return token.refreshToken
        }
        guard let refreshToken else { return }

        let newToken = try await SkylightAuth.refresh(token: refreshToken, fingerprint: fingerprint, session: session)

        state.withLock { $0 = newToken }
        onRefresh?(newToken)
    }
}
