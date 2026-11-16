import ArgumentParser

@main
struct PhotoSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "photosync",
        abstract: "Sync an iCloud Photo Album to a Skylight frame.",
        subcommands: [
            LoginCommand.self,
            SyncCommand.self,
            StatusCommand.self,
            ConfigCommand.self,
            DaemonCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
        ]
    )
}
