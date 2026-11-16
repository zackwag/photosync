#if canImport(Photos)
import Foundation
import Photos

/// Reads photos from iCloud Photo Albums via PhotoKit.
public final class PhotoKitReader: PhotoReading, @unchecked Sendable {
    public init() {}

    public func albums() throws -> [(id: String, title: String)] {
        try checkAccess()
        var result: [(id: String, title: String)] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            result.append((id: collection.localIdentifier, title: collection.localizedTitle ?? "(untitled)"))
        }
        return result
    }

    public func albumAssetIDs(albumID: String) throws -> Set<String> {
        try checkAccess()
        guard let collection = fetchAlbum(id: albumID) else {
            throw PhotoReaderError.albumNotFound(albumID)
        }
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: collection, options: opts)
        var ids = Set<String>()
        assets.enumerateObjects { asset, _, _ in
            ids.insert(asset.localIdentifier)
        }
        return ids
    }

    public func imageData(assetID: String) throws -> (data: Data, ext: String) {
        try checkAccess()
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = result.firstObject else {
            throw PhotoReaderError.assetNotFound(assetID)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var imageData: Data?
        var uti: String?
        var exportError: Error?

        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, _, info in
            imageData = data
            uti = dataUTI
            exportError = info?[PHImageErrorKey] as? Error
            semaphore.signal()
        }
        semaphore.wait()

        if let err = exportError {
            throw PhotoReaderError.exportFailed(err.localizedDescription)
        }
        guard let data = imageData else {
            throw PhotoReaderError.exportFailed("no data returned for asset \(assetID)")
        }

        let ext = extensionForUTType(uti ?? "")
        return (data: data, ext: ext)
    }

    // MARK: - Private

    private func fetchAlbum(id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private func checkAccess() throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .denied || status == .restricted {
            throw PhotoReaderError.accessDenied
        }
    }
}
#endif
