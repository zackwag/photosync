#if canImport(UserNotifications)
import UserNotifications

/// Posts native macOS notifications.
public enum Notifier {
    /// Requests notification permission.
    public static func requestPermission() async throws {
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Sends a notification with the given title and body.
    public static func send(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
#endif
