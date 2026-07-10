import Foundation
import UserNotifications

struct ThresholdTracker {
    enum Event {
        case crossedThreshold(Int)
        case reset
    }

    private var armedAbove: [String: Bool] = [:]
    private var nilStreak: [String: Int] = [:]

    /// Emits .crossedThreshold exactly when value crosses from below to >= threshold,
    /// and .reset when a section that was above threshold goes back to nil.
    /// A nil value means the section reset (parser emits nil, not 0), so it
    /// re-arms the threshold — but only after two consecutive nils, because a
    /// single nil can also be a transient failed parse and re-arming on it
    /// would duplicate the alert on the next good poll. A real reset stays
    /// nil for many minutes, so two ticks still re-arms promptly. .reset fires
    /// once, on the tick that disarms; only sections that had crossed the
    /// threshold emit it, so an idle 5h cycle stays silent.
    mutating func evaluate(value: Int?, threshold: Int, label: String) -> Event? {
        guard let value else {
            let streak = (nilStreak[label] ?? 0) + 1
            nilStreak[label] = streak
            if streak >= 2 && armedAbove[label] == true {
                armedAbove[label] = false
                return .reset
            }
            return nil
        }
        nilStreak[label] = 0
        let above = value >= threshold
        let wasAbove = armedAbove[label] ?? false
        armedAbove[label] = above
        if above && !wasAbove {
            return .crossedThreshold(value)
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
        handle(tracker.evaluate(value: state.sessionPercent,
                                threshold: settings.sessionThreshold, label: "Session"),
               threshold: settings.sessionThreshold, label: "Session", settings: settings)
        handle(tracker.evaluate(value: state.weeklyPercent,
                                threshold: settings.weeklyThreshold, label: "Weekly"),
               threshold: settings.weeklyThreshold, label: "Weekly", settings: settings)
    }

    // Gate the reset alert here (not in the tracker) so toggling the setting
    // never desyncs the tracker's armed state.
    private func handle(_ event: ThresholdTracker.Event?, threshold: Int,
                        label: String, settings: SettingsStore) {
        switch event {
        case .crossedThreshold(let value):
            post("\(label) usage at \(value)% (threshold \(threshold)%)")
        case .reset:
            if settings.notifyOnReset {
                post("\(label) limit reset — you can use Claude again.")
            }
        case nil:
            break
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
