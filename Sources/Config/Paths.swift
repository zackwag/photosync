import Foundation

/// Standard file paths for PhotoSync data.
public enum Paths {
    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoSync")
    }

    /// `~/Library/Application Support/PhotoSync/config.json`
    public static var configURL: URL {
        appSupport.appendingPathComponent("config.json")
    }

    /// `~/Library/Application Support/PhotoSync/state.db`
    public static var stateURL: URL {
        appSupport.appendingPathComponent("state.db")
    }

    /// `~/Library/Logs/PhotoSync/daemon.log`
    public static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
            .appendingPathComponent("PhotoSync")
            .appendingPathComponent("daemon.log")
    }

    /// `~/Library/Logs/PhotoSync/`
    public static var logDir: URL {
        logURL.deletingLastPathComponent()
    }
}
