import ServiceManagement

final class LaunchAtLogin {
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchAtLogin failed: \(error.localizedDescription)")
        }
    }

    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}
