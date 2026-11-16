import ArgumentParser
import Foundation
import SkylightClient
import Config
import PhotoReader

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Interactive setup: choose an album and a Skylight frame."
    )

    mutating func run() async throws {
        #if canImport(Photos)
        let reader: PhotoReading = PhotoKitReader()
        #else
        fatalError("PhotoSync requires macOS with Photos framework")
        #endif

        // Select album
        let albumList = try reader.albums()
        guard !albumList.isEmpty else {
            print("No photo albums found. Create one in Photos first.")
            return
        }
        print("Photo albums:\n")
        for (i, album) in albumList.enumerated() {
            print("  \(i + 1). \(album.title)")
        }
        print()
        let albumIndex = try readSelection(prompt: "Select album", max: albumList.count)
        let album = albumList[albumIndex]

        // Ensure credentials
        let creds: SkylightCredentials
        do {
            creds = try CredentialStore.load()
        } catch {
            print("\nNo Skylight credentials found. Run `photosync login` first.")
            throw ExitCode.failure
        }

        // Select frame
        let client = SkylightClient(token: creds.token, fingerprint: creds.fingerprint)
        let frames = try await client.frames()
        guard !frames.isEmpty else {
            print("No Skylight frames found on this account.")
            return
        }
        print("\nSkylight frames:\n")
        for (i, frame) in frames.enumerated() {
            print("  \(i + 1). \(frame.name)")
        }
        print()
        let frameIndex = try readSelection(prompt: "Select frame", max: frames.count)
        let frame = frames[frameIndex]

        let config = SyncConfig(albumID: album.id, albumTitle: album.title, frameID: frame.id, frameName: frame.name)
        try SyncConfig.save(config, to: Paths.configURL)
        print("\nConfig saved: \(album.title) -> \(frame.name)")
    }

    private func readSelection(prompt: String, max: Int) throws -> Int {
        while true {
            print("\(prompt) [1-\(max)]: ", terminator: "")
            guard let line = readLine(strippingNewline: true), let n = Int(line), n >= 1, n <= max else {
                print("Invalid selection. Try again.")
                continue
            }
            return n - 1
        }
    }
}
