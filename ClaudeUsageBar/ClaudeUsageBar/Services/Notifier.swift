import Foundation
import UserNotifications

struct ThresholdTracker {
    private var armedAbove: [String: Bool] = [:]
    private var nilStreak: [String: Int] = [:]

    /// Returns a message exactly when value crosses from below to >= threshold.
    /// A nil value means the section reset (parser emits nil, not 0), so it
    /// re-arms the threshold — but only after two consecutive nils, because a
    /// single nil can also be a transient failed parse and re-arming on it
    /// would duplicate the alert on the next good poll. A real reset stays
    /// nil for many minutes, so two ticks still re-arms promptly.
    mutating func evaluate(value: Int?, threshold: Int, label: String) -> String? {
        guard let value else {
            let streak = (nilStreak[label] ?? 0) + 1
            nilStreak[label] = streak
            if streak >= 2 { armedAbove[label] = false }
            return nil
        }
        nilStreak[label] = 0
        let above = value >= threshold
        let wasAbove = armedAbove[label] ?? false
        armedAbove[label] = above
        if above && !wasAbove {
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

    /// Manual delivery check from Settings, so users can verify alerts work.
    func postTest() {
        post("Test notification — alerts are working.")
    }

    private func post(_ body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus != .authorized {
                NSLog("Notifier: not authorized (status \(settings.authorizationStatus.rawValue)); alert may be dropped: \(body)")
            }
            let content = UNMutableNotificationContent()
            content.title = "Claude Usage Bar"
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req) { error in
                if let error { NSLog("Notifier: add failed: \(error.localizedDescription)") }
            }
        }
    }
}
