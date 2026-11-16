import ArgumentParser
import Foundation
import SkylightClient
import SyncEngine
import State
import Config
import PhotoReader

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync album photos to Skylight."
    )

    @Flag(name: .long, help: "Preview changes without applying them.")
    var dryRun = false

    @Flag(name: .long, help: "Skip the mass-delete safety limit.")
    var force = false

    mutating func run() async throws {
        let config = try SyncConfig.load(from: Paths.configURL)
        let creds = try CredentialStore.load()
        let store = try StateStore(path: Paths.stateURL.path)
        defer { store.close() }

        let client = SkylightClient(
            token: creds.token,
            fingerprint: creds.fingerprint,
            onRefresh: { newToken in
                var updated = creds
                updated.token = newToken
                try? CredentialStore.save(updated)
            }
        )

        #if canImport(Photos)
        let reader: PhotoReading = PhotoKitReader()
        #else
        fatalError("PhotoSync requires macOS with Photos framework")
        #endif

        try await reader.requestAccess()
        let albumIDs = try reader.albumAssetIDs(albumID: config.albumID)
        let records = try store.listAll()
        let plan = SyncEngine.plan(albumAssetIDs: albumIDs, stateRecords: records, force: force)

        let nonPendingCount = records.filter { !$0.pending }.count
        if !force && SyncEngine.massDeleteExceeded(deleteCount: plan.deletes.count, totalLinked: nonPendingCount) {
            print("Refusing to delete \(plan.deletes.count) of \(nonPendingCount) photos (safety limit).")
            print("Run with --force to override.")
            return
        }

        if dryRun {
            printPlan(plan)
            return
        }

        // Execute uploads
        for assetID in plan.uploads {
            do {
                let (data, ext) = try reader.imageData(assetID: assetID)
                let result = try await client.upload(frameID: config.frameID, ext: ext, imageData: data)
                try store.insert(assetID: assetID, messageID: result.messageID, pending: true)
                try store.clearPending(assetID: assetID)
                print("  uploaded \(assetID) -> \(result.messageID)")
            } catch {
                print("  upload failed for \(assetID): \(error.localizedDescription)")
            }
        }

        // Execute deletes
        if !plan.deletes.isEmpty {
            let messageIDs = plan.deletes.map(\.messageID)
            do {
                try await client.deleteMessages(frameID: config.frameID, ids: messageIDs)
                let assetIDs = plan.deletes.map(\.assetID)
                try store.deleteAll(assetIDs: assetIDs)
                print("  deleted \(messageIDs.count) photos from Skylight")
            } catch {
                print("  delete failed: \(error.localizedDescription)")
            }
        }

        let total = try store.listAll().count
        print("Sync complete. \(plan.uploads.count) uploaded, \(plan.deletes.count) deleted. \(total) photos linked.")
    }

    private func printPlan(_ plan: SyncPlan) {
        if plan.uploads.isEmpty && plan.deletes.isEmpty {
            print("Nothing to sync.")
            return
        }
        if !plan.uploads.isEmpty {
            print("Would upload \(plan.uploads.count) photo(s):")
            for id in plan.uploads.prefix(10) {
                print("  + \(id)")
            }
            if plan.uploads.count > 10 {
                print("  ... and \(plan.uploads.count - 10) more")
            }
        }
        if !plan.deletes.isEmpty {
            print("Would delete \(plan.deletes.count) photo(s):")
            for d in plan.deletes.prefix(10) {
                print("  - \(d.assetID) (message \(d.messageID))")
            }
            if plan.deletes.count > 10 {
                print("  ... and \(plan.deletes.count - 10) more")
            }
        }
    }
}
