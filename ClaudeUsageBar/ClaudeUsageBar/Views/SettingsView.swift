import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let session: ClaudeSession
    let launch: LaunchAtLogin
    var onIntervalChange: () -> Void
    var onAuthChange: () -> Void
    var onTestNotification: () -> Void

    @State private var interval: Double
    @State private var sessionThreshold: Double
    @State private var weeklyThreshold: Double
    @State private var launchEnabled: Bool
    @State private var authed = false

    init(settings: SettingsStore, session: ClaudeSession, launch: LaunchAtLogin,
         onIntervalChange: @escaping () -> Void, onAuthChange: @escaping () -> Void = {},
         onTestNotification: @escaping () -> Void = {}) {
        self.settings = settings; self.session = session; self.launch = launch
        self.onIntervalChange = onIntervalChange
        self.onAuthChange = onAuthChange
        self.onTestNotification = onTestNotification
        _interval = State(initialValue: Double(settings.pollIntervalSeconds))
        _sessionThreshold = State(initialValue: Double(settings.sessionThreshold))
        _weeklyThreshold = State(initialValue: Double(settings.weeklyThreshold))
        _launchEnabled = State(initialValue: settings.launchAtLogin)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button(authed ? "Log out" : "Log in") {
                        Task {
                            if authed { await session.logout() } else { session.openLogin() }
                            authed = await session.isAuthenticated()
                            onAuthChange()
                        }
                    }
                    .controlSize(.large)
                } label: {
                    Text(authed ? "Signed in" : "Not signed in")
                }
            } header: {
                Label("Account", systemImage: "person.crop.circle")
            }

            Section {
                LabeledContent("Interval") {
                    Text("\(Int(interval))s").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $interval, in: 30...300, step: 10)
                    .onChange(of: interval) { _, v in settings.pollIntervalSeconds = Int(v); onIntervalChange() }
            } header: {
                Label("Polling", systemImage: "clock.arrow.circlepath")
            }

            Section {
                LabeledContent("Session alert") {
                    Text("\(Int(sessionThreshold))%").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $sessionThreshold, in: 50...100, step: 5)
                    .onChange(of: sessionThreshold) { _, v in settings.sessionThreshold = Int(v) }
                LabeledContent("Weekly alert") {
                    Text("\(Int(weeklyThreshold))%").foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $weeklyThreshold, in: 50...100, step: 5)
                    .onChange(of: weeklyThreshold) { _, v in settings.weeklyThreshold = Int(v) }
                Button("Send test notification") { onTestNotification() }
            } header: {
                Label("Notifications", systemImage: "bell.badge")
            }

            Section {
                Toggle("Launch at login", isOn: $launchEnabled)
                    .onChange(of: launchEnabled) { _, v in settings.launchAtLogin = v; launch.setEnabled(v) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 360, height: 420)
        .background(VisualEffectBackground().ignoresSafeArea())
        .task {
            authed = await session.isAuthenticated()
            launchEnabled = launch.isEnabled   // reflect real SMAppService state, not just stored flag
        }
    }
}
