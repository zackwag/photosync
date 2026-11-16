import Foundation

enum LogRotation {
    private static let maxSize: UInt64 = 5 * 1024 * 1024 // 5 MB

    /// Rotates the log file if it exceeds 5 MB.
    /// Renames current to `.1`, opens fresh, and redirects stdout/stderr via dup2.
    static func rotateIfNeeded(logPath: String) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64,
              size > maxSize else {
            return
        }

        let rotated = logPath + ".1"
        try? fm.removeItem(atPath: rotated)
        try? fm.moveItem(atPath: logPath, toPath: rotated)

        // Open a new log file and redirect stdout/stderr.
        guard let fd = fopen(logPath, "a") else { return }
        let fileno = fileno(fd)
        dup2(fileno, STDOUT_FILENO)
        dup2(fileno, STDERR_FILENO)
        fclose(fd)
    }
}
