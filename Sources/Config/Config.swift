import Foundation
import SkylightClient

/// Sync configuration persisted in config.json.
public struct SyncConfig: Codable, Sendable, Equatable {
    public var albumID: String
    public var albumTitle: String
    public var frameID: String
    public var frameName: String
    public var pollInterval: Int

    enum CodingKeys: String, CodingKey {
        case albumID = "album_id"
        case albumTitle = "album_title"
        case frameID = "frame_id"
        case frameName = "frame_name"
        case pollInterval = "poll_interval"
    }

    public init(albumID: String, albumTitle: String, frameID: String, frameName: String, pollInterval: Int = 300) {
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.frameID = frameID
        self.frameName = frameName
        self.pollInterval = pollInterval
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumID = try c.decode(String.self, forKey: .albumID)
        albumTitle = try c.decode(String.self, forKey: .albumTitle)
        frameID = try c.decode(String.self, forKey: .frameID)
        frameName = try c.decode(String.self, forKey: .frameName)
        pollInterval = try c.decodeIfPresent(Int.self, forKey: .pollInterval) ?? 300
    }

    /// Loads config from a file URL. Throws `ConfigError.notFound` if the
    /// file doesn't exist, so callers can point at `photosync config`.
    public static func load(from url: URL) throws -> SyncConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.notFound(url.path)
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(SyncConfig.self, from: data)
        } catch {
            throw ConfigError.invalid(url.path, error.localizedDescription)
        }
    }

    /// Saves config to a file URL, creating the parent directory if needed.
    public static func save(_ config: SyncConfig, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}

/// Errors from loading the config file.
public enum ConfigError: Error, LocalizedError, Equatable {
    case notFound(String)
    case invalid(String, String)

    public var errorDescription: String? {
        switch self {
        case .notFound: "PhotoSync isn't set up yet. Run `photosync config` to pick an album and a frame."
        case .invalid(let path, let reason): "Couldn't read \(path): \(reason). Run `photosync config` to write a new one."
        }
    }
}
