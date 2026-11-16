import CryptoKit
import Foundation

/// Skylight OAuth2 + PKCE authentication.
public enum SkylightAuth {
    public static let baseURL = "https://app.ourskylight.com"

    static let clientID = "skylight-mobile"
    static let scope = "everything"
    static let redirectURI = "https://ourskylight.com/welcome"

    /// RFC 7636 code verifier and S256 challenge.
    public struct PKCE: Sendable {
        public var verifier: String
        public var challenge: String

        public static func generate() throws -> PKCE {
            var bytes = [UInt8](repeating: 0, count: 64)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw PKCEError.randomGenerationFailed
            }
            let verifier = Data(bytes).base64URLEncoded()
            let hash = SHA256.hash(data: Data(verifier.utf8))
            let challenge = Data(hash).base64URLEncoded()
            return PKCE(verifier: verifier, challenge: challenge)
        }
    }

    enum PKCEError: Error {
        case randomGenerationFailed
    }

    /// Generates a random device fingerprint for this install.
    public static func newFingerprint() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PKCEError.randomGenerationFailed
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The login URL to open in a browser.
    public static func authorizeURL(challenge: String) -> URL {
        var components = URLComponents(string: "\(baseURL)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "login"),
        ]
        return components.url!
    }

    /// Extracts the authorization code from a bare code, a redirect URL, or "code=..." prefix.
    public static func extractCode(from raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExtractCodeError.empty
        }
        if trimmed.contains("://") || trimmed.hasPrefix("/") {
            guard let components = URLComponents(string: trimmed),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty else {
                throw ExtractCodeError.noCodeParam
            }
            return code
        }
        if trimmed.lowercased().hasPrefix("code=") {
            return String(trimmed.dropFirst(5))
        }
        return trimmed
    }

    enum ExtractCodeError: Error {
        case empty
        case noCodeParam
    }

    /// Exchange an authorization code for tokens.
    public static func exchangeCode(
        _ code: String, verifier: String, fingerprint: String, session: URLSession = .shared
    ) async throws -> Token {
        var form: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("code_verifier", verifier),
            ("scope", scope),
            ("source", "js-mobile"),
        ]
        addDeviceParams(&form, fingerprint: fingerprint, osVersion: "unknown")
        let token = try await tokenRequest(form: form, session: session)
        guard !token.refreshToken.isEmpty else {
            throw TokenError.noRefreshToken
        }
        return token
    }

    /// Refresh an access token.
    public static func refresh(
        token refreshToken: String, fingerprint: String, session: URLSession = .shared
    ) async throws -> Token {
        var form: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
            ("scope", scope),
            ("source", "web"),
        ]
        addDeviceParams(&form, fingerprint: fingerprint, osVersion: "10")
        var token = try await tokenRequest(form: form, session: session)
        if token.refreshToken.isEmpty {
            token.refreshToken = refreshToken
        }
        return token
    }

    enum TokenError: Error {
        case noRefreshToken
        case noAccessToken
        case httpError(Int, String)
    }

    // MARK: - Private

    private static func addDeviceParams(_ form: inout [(String, String)], fingerprint: String, osVersion: String) {
        form.append(("skylight_api_client_device_fingerprint", fingerprint))
        form.append(("skylight_api_client_device_platform", "web"))
        form.append(("skylight_api_client_device_name", "photosync"))
        form.append(("skylight_api_client_device_os_version", osVersion))
        form.append(("skylight_api_client_device_app_version", "unknown"))
        form.append(("skylight_api_client_device_hardware", "3"))
    }

    private static func tokenRequest(form: [(String, String)], session: URLSession) async throws -> Token {
        let url = URL(string: "\(baseURL)/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SkylightClient.userAgent, forHTTPHeaderField: "User-Agent")

        let body = form.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.1)" }
            .joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        let httpResp = response as! HTTPURLResponse
        guard httpResp.statusCode == 200 else {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TokenError.httpError(httpResp.statusCode, body)
        }
        let token = try JSONDecoder().decode(Token.self, from: data)
        guard !token.accessToken.isEmpty else {
            throw TokenError.noAccessToken
        }
        return token
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
