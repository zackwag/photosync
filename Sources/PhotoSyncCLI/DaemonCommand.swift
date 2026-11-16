import ArgumentParser
import Foundation
import SkylightClient
import SyncEngine
import State
import Config
import PhotoReader
import Notify

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the sync daemon (managed by launchd)."
    )

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

        var tracker = AlertTracker()
        let interval = TimeInterval(config.pollInterval)
        let binaryPath = ProcessInfo.processInfo.arguments[0]

        print("[\(Self.timestamp())] daemon started, polling every \(config.pollInterval)s")

        #if canImport(Photos)
        // Register for photo library changes.
        let observer = ChangeObserver(debounceInterval: 2.0) {
            print("[\(DaemonCommand.timestamp())] photo library changed, triggering sync")
        }
        _ = observer // keep alive
        #endif

        // Run the main sync loop.
        while !Task.isCancelled {
            LogRotation.rotateIfNeeded(logPath: Paths.logURL.path)

            do {
                try await syncOnce(config: config, client: client, reader: reader, store: store)
                let action = tracker.recordSuccess()
                if action == .recoveryAlert {
                    #if canImport(UserNotifications)
                    try? await Notifier.send(title: "PhotoSync", body: "Sync recovered")
                    #endif
                }
            } catch {
                print("[\(Self.timestamp())] sync error: \(error.localizedDescription)")
                let isAuth = error is CredentialError
                let action = tracker.recordFailure(at: Date(), isAuthError: isAuth)
                if action == .alert {
                    #if canImport(UserNotifications)
                    try? await Notifier.send(title: "PhotoSync", body: "Sync failing: \(error.localizedDescription)")
                    #endif
                }
            }

            // Check if our binary has been replaced (brew upgrade).
            if binaryChanged(binaryPath) {
                print("[\(Self.timestamp())] binary changed, exiting for relaunch")
                throw ExitCode(1)
            }

            try await Task.sleep(for: .seconds(interval))
        }
    }

    private func syncOnce(
        config: SyncConfig, client: SkylightClient, reader: PhotoReading, store: StateStore
    ) async throws {
        let albumIDs = try reader.albumAssetIDs(albumID: config.albumID)
        let records = try store.listAll()
        let plan = SyncEngine.plan(albumAssetIDs: albumIDs, stateRecords: records, force: false)

        let nonPendingCount = records.filter { !$0.pending }.count
        if SyncEngine.massDeleteExceeded(deleteCount: plan.deletes.count, totalLinked: nonPendingCount) {
            print("[\(Self.timestamp())] mass delete blocked: \(plan.deletes.count) of \(nonPendingCount)")
            return
        }

        if plan.uploads.isEmpty && plan.deletes.isEmpty {
            return
        }

        for assetID in plan.uploads {
            let (data, ext) = try reader.imageData(assetID: assetID)
            let result = try await client.upload(frameID: config.frameID, ext: ext, imageData: data)
            try store.insert(assetID: assetID, messageID: result.messageID, pending: true)
            try store.clearPending(assetID: assetID)
            print("[\(Self.timestamp())] uploaded \(assetID) -> \(result.messageID)")
        }

        if !plan.deletes.isEmpty {
            try await client.deleteMessages(frameID: config.frameID, ids: plan.deletes.map(\.messageID))
            try store.deleteAll(assetIDs: plan.deletes.map(\.assetID))
            print("[\(Self.timestamp())] deleted \(plan.deletes.count) photos")
        }
    }

    private func binaryChanged(_ path: String) -> Bool {
        struct StartInfo {
            static let mtime: Date? = {
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: ProcessInfo.processInfo.arguments[0]),
                      let date = attrs[.modificationDate] as? Date else { return nil }
                return date
            }()
        }
        guard let startMtime = StartInfo.mtime,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let current = attrs[.modificationDate] as? Date else {
            return false
        }
        return current != startMtime
    }

    fileprivate static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
