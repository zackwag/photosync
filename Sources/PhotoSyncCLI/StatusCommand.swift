import ArgumentParser
import Foundation
import State
import Config

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show sync status."
    )

    mutating func run() async throws {
        let config = try SyncConfig.load(from: Paths.configURL)
        let store = try StateStore(path: Paths.stateURL.path)
        defer { store.close() }

        let records = try store.listAll()
        let pending = records.filter(\.pending).count
        let linked = records.count - pending

        print("Album:   \(config.albumTitle)")
        print("Frame:   \(config.frameName)")
        print("Linked:  \(linked)")
        if pending > 0 {
            print("Pending: \(pending)")
        }
        print("Poll:    every \(config.pollInterval)s")
    }
}
