import State

/// The result of comparing album contents against stored state.
public struct SyncPlan: Sendable, Equatable {
    /// Asset IDs that need uploading (new or pending re-uploads).
    public var uploads: [String]
    /// Records to delete from Skylight (asset removed from album).
    public var deletes: [(assetID: String, messageID: String)]

    public init(uploads: [String] = [], deletes: [(assetID: String, messageID: String)] = []) {
        self.uploads = uploads
        self.deletes = deletes
    }

    public static func == (lhs: SyncPlan, rhs: SyncPlan) -> Bool {
        lhs.uploads == rhs.uploads
            && lhs.deletes.count == rhs.deletes.count
            && zip(lhs.deletes, rhs.deletes).allSatisfy { $0.assetID == $1.assetID && $0.messageID == $1.messageID }
    }
}

/// Pure diff logic: no I/O, no network, no database.
public enum SyncEngine {
    /// Compares album asset IDs against state records and returns
    /// the uploads and deletes needed to bring Skylight in sync.
    public static func plan(
        albumAssetIDs: Set<String>,
        stateRecords: [PhotoRecord],
        force: Bool
    ) -> SyncPlan {
        // Build lookup from state.
        var stateByAsset: [String: PhotoRecord] = [:]
        for record in stateRecords {
            stateByAsset[record.assetID] = record
        }

        var uploads: [String] = []
        var deletes: [(assetID: String, messageID: String)] = []

        // Assets in album but not in state (or pending) → upload.
        for assetID in albumAssetIDs {
            if let record = stateByAsset[assetID] {
                if record.pending {
                    uploads.append(assetID)
                }
                // else: already synced, no action
            } else {
                uploads.append(assetID)
            }
        }

        // State records whose asset is no longer in the album → delete.
        for record in stateRecords {
            if !albumAssetIDs.contains(record.assetID) {
                deletes.append((assetID: record.assetID, messageID: record.messageID))
            }
        }

        return SyncPlan(uploads: uploads.sorted(), deletes: deletes)
    }

    /// Returns true if the delete count exceeds the safety limit: max(5, 25% of total linked).
    public static func massDeleteExceeded(deleteCount: Int, totalLinked: Int) -> Bool {
        let threshold = max(5, totalLinked / 4)
        return deleteCount > threshold
    }
}
