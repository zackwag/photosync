import ArgumentParser
import Foundation
import SkylightClient
import Config

struct LoginCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Authenticate with Skylight."
    )

    mutating func run() async throws {
        let pkce = try SkylightAuth.PKCE.generate()
        let fingerprint = try SkylightAuth.newFingerprint()
        let url = SkylightAuth.authorizeURL(challenge: pkce.challenge)

        print("Open this URL in your browser to log in:\n")
        print("  \(url.absoluteString)\n")
        print("After logging in, paste the full redirect URL or the code here:")

        guard let raw = readLine(strippingNewline: true), !raw.isEmpty else {
            throw LoginError.noInput
        }

        let code = try SkylightAuth.extractCode(from: raw)
        print("Exchanging code...")
        let token = try await SkylightAuth.exchangeCode(code, verifier: pkce.verifier, fingerprint: fingerprint)

        let creds = SkylightCredentials(token: token, fingerprint: fingerprint)
        try CredentialStore.save(creds)
        print("Logged in. Credentials saved to Keychain.")
    }
}

enum LoginError: Error, LocalizedError {
    case noInput

    var errorDescription: String? {
        "no input provided"
    }
}
