import Foundation

/// Protocol for reading photos from an album.
public protocol PhotoReading: Sendable {
    /// Returns all asset IDs in the given album.
    func albumAssetIDs(albumID: String) throws -> Set<String>
    /// Returns the image data and file extension for an asset.
    func imageData(assetID: String) throws -> (data: Data, ext: String)
    /// Lists all user albums.
    func albums() throws -> [(id: String, title: String)]
}

public enum PhotoReaderError: Error, LocalizedError {
    case albumNotFound(String)
    case assetNotFound(String)
    case exportFailed(String)
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .albumNotFound(let id): "album not found: \(id)"
        case .assetNotFound(let id): "asset not found: \(id)"
        case .exportFailed(let msg): "photo export failed: \(msg)"
        case .accessDenied: "Photos access denied — open System Settings > Privacy & Security > Photos and enable PhotoSync"
        }
    }
}
