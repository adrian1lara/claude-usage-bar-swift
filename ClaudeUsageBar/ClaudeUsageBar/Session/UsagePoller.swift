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

        // Scrape first, don't pre-check cookies: WKHTTPCookieStore.allCookies()
        // reads through the WebKit network process, which doesn't exist until a
        // web view has loaded — at cold launch it reports 0 cookies even when a
        // valid session is on disk, which parked the app on "signed out".
        let newState = await session.fetchUsageViaDOM()
        NSLog("UsagePoller: fetched session=%@ weekly=%@",
              newState.sessionPercent.map(String.init) ?? "nil",
              newState.weeklyPercent.map(String.init) ?? "nil")
        if !newState.isEmpty {
            state = newState
            onUpdate?(newState)
            return
        }
        // Empty parse: signed out vs transient page failure. The cookie store is
        // trustworthy here because the scraper's web view just ran.
        if await session.isAuthenticated() {
            return   // keep last good state; next poll retries
        }
        state = .signedOut
        onUpdate?(state)
    }
}
