import Foundation

/// Protocol for reading photos from an album.
public protocol PhotoReading: Sendable {
    /// Asks for Photos access if it hasn't been decided yet, and throws unless
    /// full access is granted. Call before any read.
    func requestAccess() async throws
    /// Returns all asset IDs in the given album.
    func albumAssetIDs(albumID: String) throws -> Set<String>
    /// Returns the image data and file extension for an asset.
    func imageData(assetID: String) throws -> (data: Data, ext: String)
    /// Lists all user albums.
    func albums() throws -> [(id: String, title: String)]
}

public enum PhotoReaderError: Error, LocalizedError, Equatable {
    case albumNotFound(String)
    case assetNotFound(String)
    case exportFailed(String)
    case accessDenied
    case accessLimited
    case accessNotDetermined

    public var errorDescription: String? {
        switch self {
        case .albumNotFound(let id): "album not found: \(id)"
        case .assetNotFound(let id): "asset not found: \(id)"
        case .exportFailed(let msg): "photo export failed: \(msg)"
        case .accessDenied: "Photos access denied. Turn it on in System Settings > Privacy & Security > Photos, for PhotoSync (the daemon) or your terminal app (commands run from a terminal)"
        case .accessLimited: "PhotoSync has limited Photos access, so albums would look partly empty. Choose Full Access in System Settings > Privacy & Security > Photos"
        case .accessNotDetermined: "Photos access hasn't been granted yet. Run `photosync config` or `photosync sync` to get the prompt"
        }
    }

    /// Whether this is a permission problem that won't fix itself.
    public var isAccessError: Bool {
        switch self {
        case .accessDenied, .accessLimited, .accessNotDetermined: true
        case .albumNotFound, .assetNotFound, .exportFailed: false
        }
    }
}
