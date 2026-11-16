import ArgumentParser
import Foundation
import Config

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the launchd daemon."
    )

    mutating func run() async throws {
        // Verify prerequisites.
        _ = try SyncConfig.load(from: Paths.configURL)
        _ = try CredentialStore.load()

        // Determine binary path: prefer the app bundle, fall back to the running binary.
        let binaryPath = resolveBinaryPath()

        // Ensure log directory exists.
        try FileManager.default.createDirectory(at: Paths.logDir, withIntermediateDirectories: true)

        // Write plist.
        let plist = Launchd.plist(binary: binaryPath, logPath: Paths.logURL.path)
        try plist.write(to: Launchd.plistURL, atomically: true, encoding: .utf8)
        print("Wrote \(Launchd.plistURL.path)")

        // Bootstrap the agent.
        let uid = getuid()
        let result = try shell("launchctl", "bootstrap", "gui/\(uid)", Launchd.plistURL.path)
        if result.status != 0 && !result.output.contains("already bootstrapped") {
            print("launchctl bootstrap failed: \(result.output)")
            throw ExitCode.failure
        }
        print("Daemon installed and started.")
    }

    private func resolveBinaryPath() -> String {
        let exec = ProcessInfo.processInfo.arguments[0]
        // If running from an app bundle, use that path.
        if exec.contains(".app/Contents/MacOS/") {
            return exec
        }
        // Resolve symlinks (e.g., Homebrew).
        let resolved = (exec as NSString).resolvingSymlinksInPath
        return resolved
    }
}

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall the launchd daemon."
    )

    mutating func run() async throws {
        let uid = getuid()
        let _ = try shell("launchctl", "bootout", "gui/\(uid)/\(Launchd.label)")
        try? FileManager.default.removeItem(at: Launchd.plistURL)
        print("Daemon uninstalled. Config and state kept.")
    }
}

/// Runs a shell command and returns its output and exit status.
@discardableResult
func shell(_ args: String...) throws -> (output: String, status: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (output, process.terminationStatus)
}
