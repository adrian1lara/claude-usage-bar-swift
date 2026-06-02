import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let interval = "pollIntervalSeconds"
        static let launch = "launchAtLogin"
        static let sessionThreshold = "sessionThreshold"
        static let weeklyThreshold = "weeklyThreshold"
    }

    var pollIntervalSeconds: Int {
        get { defaults.object(forKey: Key.interval) as? Int ?? 60 }
        set { defaults.set(max(30, newValue), forKey: Key.interval) }
    }
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launch) }
        set { defaults.set(newValue, forKey: Key.launch) }
    }
    var sessionThreshold: Int {
        get { defaults.object(forKey: Key.sessionThreshold) as? Int ?? 80 }
        set { defaults.set(min(100, max(1, newValue)), forKey: Key.sessionThreshold) }
    }
    var weeklyThreshold: Int {
        get { defaults.object(forKey: Key.weeklyThreshold) as? Int ?? 80 }
        set { defaults.set(min(100, max(1, newValue)), forKey: Key.weeklyThreshold) }
    }
}
