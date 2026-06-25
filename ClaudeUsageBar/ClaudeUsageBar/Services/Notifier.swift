import Foundation
import UserNotifications

struct ThresholdTracker {
    private var armedAbove: [String: Bool] = [:]

    /// Returns a message exactly when value crosses from below to >= threshold.
    /// A nil value means the section reset (parser emits nil, not 0), so it
    /// re-arms the threshold for the next cycle.
    mutating func evaluate(value: Int?, threshold: Int, label: String) -> String? {
        let above = (value ?? 0) >= threshold   // nil = reset → below
        let wasAbove = armedAbove[label] ?? false
        armedAbove[label] = above
        if above && !wasAbove, let value {
            return "\(label) usage at \(value)% (threshold \(threshold)%)"
        }
        return nil
    }
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var tracker = ThresholdTracker()

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self   // must be set before requesting / presenting
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("Notifier: authorization error: \(error.localizedDescription)") }
            if !granted { NSLog("Notifier: notifications not authorized; alerts will be silent") }
        }
    }

    func check(state: UsageState, settings: SettingsStore) {
        // Always evaluate (even on nil) so a reset re-arms the threshold.
        if let msg = tracker.evaluate(value: state.sessionPercent,
                                      threshold: settings.sessionThreshold, label: "Session") {
            post(msg)
        }
        if let msg = tracker.evaluate(value: state.weeklyPercent,
                                      threshold: settings.weeklyThreshold, label: "Weekly") {
            post(msg)
        }
    }

    // Present banners even when this LSUIElement app is considered active.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func post(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Bar"
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
