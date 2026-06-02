import Foundation
import Combine

@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var state = UsageState()
    @Published private(set) var isRefreshing = false

    private let session: ClaudeSession
    private let settings: SettingsStore
    private var timer: Timer?
    var onUpdate: ((UsageState) -> Void)?

    init(session: ClaudeSession, settings: SettingsStore) {
        self.session = session
        self.settings = settings
    }

    func start() {
        restart()
        Task { await refresh() }
    }

    /// Clear the stale interval (macOS pauses timers during sleep) and reschedule.
    func restart() {
        timer?.invalidate()
        let interval = TimeInterval(settings.pollIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refreshNow() { Task { await refresh() } }

    private func refresh() async {
        guard !isRefreshing else { return }   // one fetch at a time: scraper reuses one WKWebView
        isRefreshing = true
        defer { isRefreshing = false }

        guard await session.isAuthenticated() else {
            state = .signedOut
            onUpdate?(state)
            return
        }
        let newState = await session.fetchUsageViaDOM()
        guard !newState.isEmpty else { return }
        state = newState
        onUpdate?(newState)
    }
}
