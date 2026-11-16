import Foundation

enum Launchd {
    static let label = "dev.zackwag.photosync"
    static let bundleID = "dev.zackwag.PhotoSync"

    /// Generates the launchd plist XML.
    static func plist(binary: String, logPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binary)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>ThrottleInterval</key>
            <integer>30</integer>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
            <key>AssociatedBundleIdentifiers</key>
            <string>\(bundleID)</string>
        </dict>
        </plist>
        """
    }

    /// Path to the LaunchAgent plist.
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
}
