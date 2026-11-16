import Foundation

/// Tracks consecutive sync failures and decides when to alert.
public struct AlertTracker: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case alert
        case recoveryAlert
    }

    private var streakStart: Date?
    private var alerted = false

    public init() {}

    /// Records a failure. Returns `.alert` when the user should be notified.
    public mutating func recordFailure(at now: Date, isAuthError: Bool) -> Action {
        if isAuthError {
            alerted = true
            return .alert
        }
        if streakStart == nil {
            streakStart = now
        }
        // Alert once per streak after 10 minutes of consecutive failures.
        if !alerted, let start = streakStart, now.timeIntervalSince(start) > 600 {
            alerted = true
            return .alert
        }
        return .none
    }

    /// Records a success. Returns `.recoveryAlert` if the user was previously alerted.
    public mutating func recordSuccess() -> Action {
        let wasAlerted = alerted
        streakStart = nil
        alerted = false
        return wasAlerted ? .recoveryAlert : .none
    }
}
