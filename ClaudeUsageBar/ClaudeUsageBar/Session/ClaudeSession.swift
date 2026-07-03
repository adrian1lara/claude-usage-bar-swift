import WebKit
import AppKit

@MainActor
final class ClaudeSession: NSObject {
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    /// Desktop Safari UA so Google/OAuth doesn't reject the embedded webview.
    private static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15"
    private let dataStore = WKWebsiteDataStore.default()   // persistent: keeps sessionKey
    private var scraper: WKWebView?
    private var loginWindow: NSWindow?
    private var loginWebView: WKWebView?
    private var oauthPopup: WKWebView?
    private var oauthPopupWindow: NSWindow?
    private var loginWatch: Task<Void, Never>?
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadGeneration = 0

    /// Called when the login window closes (user finished or cancelled sign-in).
    var onLoginFinished: (() -> Void)?

    // MARK: scraper

    private func makeScraper() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = Self.safariUA
        scraper = wv
        return wv
    }

    /// Destroy the scraper so the next poll builds a fresh renderer (used on wake).
    func resetScraper() { scraper = nil }

    func fetchUsageViaDOM() async -> UsageState {
        let wv = scraper ?? makeScraper()
        await load(wv, Self.usageURL)
        // Poll innerText up to 12s. The SPA can first render cached/stale usage
        // before its API fetch lands, so only trust a session percent once the
        // same value shows on two consecutive samples. Keep the latest non-empty
        // parse so a session legitimately at reset (no % yet, but plan + weekly
        // present) still shows data instead of blanking.
        var last = UsageState()
        var pendingPercent: Int?
        for _ in 0..<24 {
            let text = (try? await wv.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String ?? ""
            var state = UsageParser.parse(text)
            if !state.isEmpty { state.scrapedAt = Date(); last = state }
            ScrapeDebugDump.write(text: text, state: state)
            if let pct = state.sessionPercent {
                if pct == pendingPercent { return state }
                pendingPercent = pct
            } else {
                pendingPercent = nil
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return last
    }

    /// Resume the pending load continuation exactly once. Safe to call from the
    /// navigation delegate or the watchdog; whichever fires first wins.
    private func resumeLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    private func load(_ wv: WKWebView, _ url: URL) async {
        loadGeneration += 1
        let gen = loadGeneration
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loadContinuation = cont
            wv.load(URLRequest(url: url))
            // Watchdog: if navigation never completes (e.g. network still down
            // right after wake), unblock so refresh() can't hang forever.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard gen == loadGeneration else { return }   // a newer load owns the continuation
                resumeLoad()
            }
        }
    }

    // MARK: auth

    func isAuthenticated() async -> Bool {
        let cookies = await dataStore.httpCookieStore.allCookies()
        guard let key = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }) else {
            NSLog("ClaudeSession: no sessionKey cookie (%d cookies total)", cookies.count)
            return false
        }
        if let exp = key.expiresDate, exp < Date() {
            NSLog("ClaudeSession: sessionKey expired at \(exp)")
            return false
        }
        return true
    }

    func openLogin() {
        if let w = loginWindow { w.makeKeyAndOrderFront(nil); return }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 720), configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = Self.safariUA
        loginWebView = wv
        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        let win = NSWindow(contentRect: wv.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Sign in to Claude"
        win.contentView = wv
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        win.isReleasedWhenClosed = false
        loginWindow = win
        NSApp.activate(ignoringOtherApps: true)
        startLoginAuthWatch()
    }

    /// Claude is a SPA: after sign-in it client-side routes, so navigation callbacks
    /// don't always fire. Poll the cookie store and close the window as soon as the
    /// session is valid, so usage refreshes immediately.
    private func startLoginAuthWatch() {
        loginWatch?.cancel()
        loginWatch = Task { @MainActor in
            for _ in 0..<300 {   // ~5 min ceiling
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || loginWindow == nil { return }
                if await isAuthenticated() {
                    loginWindow?.close()
                    return
                }
            }
        }
    }

    func logout() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let claude = records.filter { $0.displayName.contains("claude.ai") || $0.displayName.contains("anthropic") }
        await dataStore.removeData(ofTypes: types, for: claude)
        resetScraper()
    }
}

/// Opt-in scrape diagnostics: `defaults write com.wavestudio.ClaudeUsageBar debugDumpScrape -bool true`
/// writes the latest raw innerText + parsed values to ~/Library/Logs/ClaudeUsageBar/scrape.txt
/// so a parser/site mismatch can be diagnosed from the exact text the app saw.
enum ScrapeDebugDump {
    private static let enabled = UserDefaults.standard.bool(forKey: "debugDumpScrape")
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ClaudeUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scrape.txt")
    }()

    static func write(text: String, state: UsageState) {
        guard enabled else { return }
        let header = """
        # \(Date())
        # parsed: session=\(state.sessionPercent.map(String.init) ?? "nil")% \
        weekly=\(state.weeklyPercent.map(String.init) ?? "nil")% \
        plan=\(state.plan ?? "nil") \
        sessionResetsIn=\(state.sessionResetsIn ?? "nil") \
        weeklyResetsAt=\(state.weeklyResetsAt ?? "nil")

        """
        try? (header + text).write(to: url, atomically: true, encoding: .utf8)
    }
}

extension ClaudeSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === loginWindow else { return }
        loginWatch?.cancel(); loginWatch = nil
        loginWindow = nil
        loginWebView = nil
        oauthPopupWindow?.close()
        oauthPopupWindow = nil
        oauthPopup = nil
        resetScraper()   // force a fresh authenticated render on next fetch
        onLoginFinished?()
    }
}

extension ClaudeSession: WKNavigationDelegate, WKUIDelegate {
    private func isLoginFlow(_ webView: WKWebView) -> Bool {
        webView === loginWebView || webView === oauthPopup
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isLoginFlow(webView) {
            // Close the sign-in UI as soon as a valid session cookie exists.
            Task { @MainActor in
                if await isAuthenticated() { loginWindow?.close() }
            }
            return
        }
        resumeLoad()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isLoginFlow(webView) else { return }
        resumeLoad()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isLoginFlow(webView) else { return }
        resumeLoad()   // DNS/connection failure (e.g. network not up yet after wake)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let host = navigationAction.request.url?.host else { decisionHandler(.cancel); return }
        if isLoginFlow(webView) {
            decisionHandler(.allow)   // sign-in: allow Claude + OAuth providers (Google, etc.)
        } else {
            decisionHandler(host.hasSuffix("claude.ai") ? .allow : .cancel)   // scraper: claude.ai only
        }
    }

    // OAuth "Continue with Google" opens a popup window — present it in its own window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.customUserAgent = Self.safariUA
        oauthPopup = popup

        let win = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Sign in"
        win.contentView = popup
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.isReleasedWhenClosed = false
        oauthPopupWindow = win
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === oauthPopup else { return }
        oauthPopupWindow?.close()
        oauthPopupWindow = nil
        oauthPopup = nil
    }
}
