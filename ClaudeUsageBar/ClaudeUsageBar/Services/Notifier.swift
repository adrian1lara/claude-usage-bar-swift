import Foundation
import UserNotifications

struct ThresholdTracker {
    private var armedAbove: [String: Bool] = [:]

    /// Returns a message exactly when value crosses from below to >= threshold.
    mutating func evaluate(value: Int, threshold: Int, label: String) -> String? {
        let above = value >= threshold
        let wasAbove = armedAbove[label] ?? false
        armedAbove[label] = above
        if above && !wasAbove {
            return "\(label) usage at \(value)% (threshold \(threshold)%)"
        }
        return nil
    }
}

final class Notifier {
    private var tracker = ThresholdTracker()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(state: UsageState, settings: SettingsStore) {
        if let p = state.sessionPercent,
           let msg = tracker.evaluate(value: p, threshold: settings.sessionThreshold, label: "Session") {
            post(msg)
        }
        if let p = state.weeklyPercent,
           let msg = tracker.evaluate(value: p, threshold: settings.weeklyThreshold, label: "Weekly") {
            post(msg)
        }
    }

    private func post(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Bar"
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
