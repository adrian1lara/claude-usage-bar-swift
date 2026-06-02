# Claude Usage Bar (Native Swift) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that shows the user's Claude session % and weekly % by scraping `claude.ai/settings/usage` with the user's own logged-in WKWebView session, with a Liquid Glass UI and four native extras.

**Architecture:** Hybrid shell — AppKit `NSStatusItem` owns the menu-bar button (text, color, click, Space handling); SwiftUI renders the popover and settings via `NSHostingController`. A `ClaudeSession` actor drives a reused hidden `WKWebView` scraper plus a visible login window, backed by a persistent `WKWebsiteDataStore`. Pure logic (parsing, settings, thresholds, formatting) is unit-tested; UI/web wiring is build-and-smoke verified.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, WebKit (`WKWebView`), Combine, `UserNotifications`, `ServiceManagement` (`SMAppService`), XCTest. Min macOS 14; Liquid Glass (`glassEffect`) on macOS 26+ with `.ultraThinMaterial` fallback. Unsigned build (`xattr -cr` to run).

---

## File Structure

```
ClaudeUsageBar.xcodeproj
ClaudeUsageBar/
  App/AppDelegate.swift          — boot, dependency wiring, sleep/wake observers
  App/Info.plist                 — LSUIElement = true
  StatusBar/StatusItemController.swift — NSStatusItem button + NSPopover
  Session/ClaudeSession.swift    — hidden WKWebView scraper + login window
  Session/UsageParser.swift      — regex parse of page text → UsageState (pure)
  Session/UsagePoller.swift      — Timer loop, immediate wake refresh
  Model/UsageState.swift         — value type for parsed usage
  Model/SettingsStore.swift      — UserDefaults-backed config (pure-ish)
  Model/UsageFormatting.swift    — percent → color + label (pure)
  Services/LaunchAtLogin.swift   — SMAppService wrapper
  Services/Notifier.swift        — threshold-cross detection + UNUserNotification
  Views/PopoverView.swift        — SwiftUI rings/bars + countdown
  Views/SettingsView.swift       — SwiftUI login/logout, interval, thresholds
  Views/GlassBackground.swift    — Liquid Glass with material fallback
  Assets.xcassets
ClaudeUsageBarTests/
  UsageParserTests.swift
  SettingsStoreTests.swift
  UsageFormattingTests.swift
  NotifierTests.swift
README.md
```

Files that change together live together (e.g. parser + its tests; session scraper + login in one folder). Pure-logic units are isolated from AppKit/WebKit so they unit-test without a running app.

---

## Task 1: Xcode project scaffold (agent app, empty status item)

**Files:**
- Create: `ClaudeUsageBar.xcodeproj` (Xcode: macOS App, SwiftUI lifecycle off — use AppKit `AppDelegate`)
- Create: `ClaudeUsageBar/App/AppDelegate.swift`
- Create: `ClaudeUsageBar/App/Info.plist`
- Create: `ClaudeUsageBar/StatusBar/StatusItemController.swift`

- [ ] **Step 1: Create the Xcode project**

In Xcode: File → New → Project → macOS → App. Product Name `ClaudeUsageBar`, Interface **AppKit App Delegate** (not SwiftUI App), Language Swift. Save into `~/repos/claude-usage-bar-swift`. Set Deployment Target to macOS 14.0. Add a Unit Testing target named `ClaudeUsageBarTests`.

- [ ] **Step 2: Mark as agent app**

In `Info.plist` add key `Application is agent (UIElement)` (`LSUIElement`) = `YES`. This removes the Dock icon.

- [ ] **Step 3: Minimal status item that shows a placeholder**

`ClaudeUsageBar/StatusBar/StatusItemController.swift`:

```swift
import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
    }
}
```

`ClaudeUsageBar/App/AppDelegate.swift`:

```swift
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }
}
```

- [ ] **Step 4: Build and run, verify menu bar shows `…`**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED. Launch from Xcode — a `…` appears in the menu bar, no Dock icon.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: scaffold agent app with placeholder status item"
```

---

## Task 2: UsageState model

**Files:**
- Create: `ClaudeUsageBar/Model/UsageState.swift`

- [ ] **Step 1: Define the value type**

```swift
import Foundation

struct UsageState: Equatable {
    var plan: String?
    var sessionPercent: Int?
    var sessionResetsIn: String?
    var weeklyPercent: Int?
    var weeklyResetsAt: String?
    var designPercent: Int?
    var scrapedAt: Date?

    var isEmpty: Bool { sessionPercent == nil && weeklyPercent == nil }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add UsageState model"
```

---

## Task 3: UsageParser (TDD — port Electron regexes)

The page text mirrors the dashboard: `Current session  XX% used  Resets in 3 hr 45 min`, `All models  XX% used  Resets Tue 12:00 AM`, plan name after `Plan usage limits`.

**Files:**
- Create: `ClaudeUsageBar/Session/UsageParser.swift`
- Test: `ClaudeUsageBarTests/UsageParserTests.swift`

- [ ] **Step 1: Write the failing test**

`ClaudeUsageBarTests/UsageParserTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBar

final class UsageParserTests: XCTestCase {
    func testParsesFullSessionAndWeekly() {
        let text = """
        Plan usage limits
        Pro
        Current session
        Resets in 3 hr 45 min
        18% used
        Weekly limits
        All models
        Resets Tue 12:00 AM
        42% used
        Claude Design
        7% used
        """
        let s = UsageParser.parse(text)
        XCTAssertEqual(s.plan, "Pro")
        XCTAssertEqual(s.sessionPercent, 18)
        XCTAssertEqual(s.sessionResetsIn, "Resets in 3 hr 45 min".isEmpty ? nil : "3 hr 45 min")
        XCTAssertEqual(s.weeklyPercent, 42)
        XCTAssertEqual(s.weeklyResetsAt, "Tue 12:00 AM")
        XCTAssertEqual(s.designPercent, 7)
    }

    func testEmptyTextReturnsEmptyState() {
        XCTAssertNil(UsageParser.parse("").sessionPercent)
    }

    func testSessionAltFallback() {
        let text = "Current session\n55% used"
        XCTAssertEqual(UsageParser.parse(text).sessionPercent, 55)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -only-testing:ClaudeUsageBarTests/UsageParserTests`
Expected: FAIL — `UsageParser` undefined.

- [ ] **Step 3: Write the implementation (port regexes to NSRegularExpression)**

`ClaudeUsageBar/Session/UsageParser.swift`:

```swift
import Foundation

enum UsageParser {
    private static func re(_ p: String) -> NSRegularExpression {
        // [.dotMatchesLineSeparators] makes "." span newlines like JS [\s\S]
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let planBlock = re(#"Plan usage limits.{0,40}?\b(Pro Max|Max|Pro|Free|Team|Enterprise)\b"#)
    private static let planFallback = try! NSRegularExpression(pattern: #"\b(Pro Max|Max|Pro|Free|Team|Enterprise)\b"#)
    private static let sessionFull = re(#"Current session.*?Resets in\s+(.+?)\s*(?:\n|$).*?(\d+)\s*%\s*used"#)
    private static let sessionAlt = re(#"Current session.*?(\d+)\s*%\s*used"#)
    private static let sessionReset = re(#"Resets in\s+([0-9]+\s*hr(?:\s*[0-9]+\s*min)?|[0-9]+\s*min)"#)
    private static let weekly = re(#"All models.*?Resets\s+(.+?)\s*(?:\n|$).*?(\d+)\s*%\s*used"#)
    private static let design = re(#"Claude Design.*?(\d+)\s*%\s*used"#)

    private static func group(_ re: NSRegularExpression, _ text: String, _ idx: Int) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > idx,
              let r = Range(m.range(at: idx), in: text) else { return nil }
        return String(text[r])
    }

    static func parse(_ text: String) -> UsageState {
        var out = UsageState()
        if text.isEmpty { return out }

        out.plan = group(planBlock, text, 1) ?? group(planFallback, text, 1)

        if let resets = group(sessionFull, text, 1), let pct = group(sessionFull, text, 2) {
            out.sessionResetsIn = resets.trimmingCharacters(in: .whitespaces)
            out.sessionPercent = Int(pct)
        } else {
            if let pct = group(sessionAlt, text, 1) { out.sessionPercent = Int(pct) }
            if let r = group(sessionReset, text, 1) { out.sessionResetsIn = r.trimmingCharacters(in: .whitespaces) }
        }

        if let resets = group(weekly, text, 1), let pct = group(weekly, text, 2) {
            out.weeklyResetsAt = resets.trimmingCharacters(in: .whitespaces)
            out.weeklyPercent = Int(pct)
        }

        if let d = group(design, text, 1) { out.designPercent = Int(d) }
        return out
    }
}
```

Note: the test's `sessionResetsIn` expectation should read `"3 hr 45 min"`. Fix the test line to `XCTAssertEqual(s.sessionResetsIn, "3 hr 45 min")` before running.

- [ ] **Step 4: Correct the test assertion and run**

Edit the test line to `XCTAssertEqual(s.sessionResetsIn, "3 hr 45 min")`.
Run: `xcodebuild test -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -only-testing:ClaudeUsageBarTests/UsageParserTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add UsageParser with ported regexes and tests"
```

---

## Task 4: SettingsStore (TDD)

**Files:**
- Create: `ClaudeUsageBar/Model/SettingsStore.swift`
- Test: `ClaudeUsageBarTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageBar

final class SettingsStoreTests: XCTestCase {
    private func freshStore() -> SettingsStore {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return SettingsStore(defaults: d)
    }

    func testDefaults() {
        let s = freshStore()
        XCTAssertEqual(s.pollIntervalSeconds, 60)
        XCTAssertEqual(s.sessionThreshold, 80)
        XCTAssertEqual(s.weeklyThreshold, 80)
        XCTAssertFalse(s.launchAtLogin)
    }

    func testIntervalClampedToMinimum() {
        let s = freshStore()
        s.pollIntervalSeconds = 5
        XCTAssertEqual(s.pollIntervalSeconds, 30)
    }

    func testPersists() {
        let s = freshStore()
        s.sessionThreshold = 95
        XCTAssertEqual(s.sessionThreshold, 95)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -only-testing:ClaudeUsageBarTests/SettingsStoreTests`
Expected: FAIL — `SettingsStore` undefined.

- [ ] **Step 3: Implement**

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: same as Step 2.
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SettingsStore with clamping and tests"
```

---

## Task 5: UsageFormatting (TDD — percent → color + label)

**Files:**
- Create: `ClaudeUsageBar/Model/UsageFormatting.swift`
- Test: `ClaudeUsageBarTests/UsageFormattingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import ClaudeUsageBar

final class UsageFormattingTests: XCTestCase {
    func testLabel() {
        XCTAssertEqual(UsageFormatting.menuBarLabel(for: nil), "—")
        XCTAssertEqual(UsageFormatting.menuBarLabel(for: 7), "7%")
        XCTAssertEqual(UsageFormatting.menuBarLabel(for: 100), "100%")
    }

    func testColorTiers() {
        XCTAssertEqual(UsageFormatting.tier(for: 10), .normal)
        XCTAssertEqual(UsageFormatting.tier(for: 75), .warn)
        XCTAssertEqual(UsageFormatting.tier(for: 95), .critical)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -only-testing:ClaudeUsageBarTests/UsageFormattingTests`
Expected: FAIL — undefined.

- [ ] **Step 3: Implement**

```swift
import AppKit

enum UsageTier { case normal, warn, critical }

enum UsageFormatting {
    static func menuBarLabel(for percent: Int?) -> String {
        guard let p = percent else { return "—" }
        return "\(p)%"
    }

    static func tier(for percent: Int) -> UsageTier {
        switch percent {
        case ..<70: return .normal
        case 70..<90: return .warn
        default: return .critical
        }
    }

    static func color(for percent: Int?) -> NSColor {
        guard let p = percent else { return .secondaryLabelColor }
        switch tier(for: p) {
        case .normal: return .systemGreen
        case .warn: return .systemOrange
        case .critical: return .systemRed
        }
    }

    static func attributedTitle(for percent: Int?) -> NSAttributedString {
        let label = menuBarLabel(for: percent)
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold).rounded()
        return NSAttributedString(string: label, attributes: [
            .font: font,
            .foregroundColor: color(for: percent),
        ])
    }
}

private extension NSFont {
    func rounded() -> NSFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add UsageFormatting (label, color tiers, rounded title)"
```

---

## Task 6: Notifier threshold-cross logic (TDD)

Pure crossing detection separated from `UNUserNotificationCenter` so it tests without permission prompts.

**Files:**
- Create: `ClaudeUsageBar/Services/Notifier.swift`
- Test: `ClaudeUsageBarTests/NotifierTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeUsageBar

final class NotifierTests: XCTestCase {
    func testFiresOnUpwardCross() {
        var t = ThresholdTracker()
        XCTAssertNil(t.evaluate(value: 50, threshold: 80, label: "Session"))
        XCTAssertEqual(t.evaluate(value: 85, threshold: 80, label: "Session"),
                       "Session usage at 85% (threshold 80%)")
    }

    func testDoesNotRefireWhileAbove() {
        var t = ThresholdTracker()
        _ = t.evaluate(value: 85, threshold: 80, label: "Session")
        XCTAssertNil(t.evaluate(value: 90, threshold: 80, label: "Session"))
    }

    func testRearmsAfterDropBelow() {
        var t = ThresholdTracker()
        _ = t.evaluate(value: 85, threshold: 80, label: "Session")
        XCTAssertNil(t.evaluate(value: 40, threshold: 80, label: "Session"))
        XCTAssertNotNil(t.evaluate(value: 90, threshold: 80, label: "Session"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -only-testing:ClaudeUsageBarTests/NotifierTests`
Expected: FAIL — `ThresholdTracker` undefined.

- [ ] **Step 3: Implement tracker + notifier shell**

```swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Notifier with threshold-cross tracker and tests"
```

---

## Task 7: ClaudeSession — hidden scraper WKWebView

**Files:**
- Create: `ClaudeUsageBar/Session/ClaudeSession.swift`

- [ ] **Step 1: Implement the scraper + login + navigation guards**

```swift
import WebKit
import AppKit

@MainActor
final class ClaudeSession: NSObject {
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    private let dataStore = WKWebsiteDataStore.default()   // persistent: keeps sessionKey
    private var scraper: WKWebView?
    private var loginWindow: NSWindow?

    // MARK: scraper

    private func makeScraper() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        scraper = wv
        return wv
    }

    /// Destroy the scraper so the next poll builds a fresh renderer (used on wake).
    func resetScraper() { scraper = nil }

    func fetchUsageViaDOM() async -> UsageState {
        let wv = scraper ?? makeScraper()
        await load(wv, Self.usageURL)
        // Poll innerText up to 12s for parsed session percent.
        for _ in 0..<24 {
            let text = (try? await wv.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String ?? ""
            var state = UsageParser.parse(text)
            if state.sessionPercent != nil {
                state.scrapedAt = Date()
                return state
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return UsageState()
    }

    private func load(_ wv: WKWebView, _ url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loadContinuation = cont
            wv.load(URLRequest(url: url))
        }
    }
    private var loadContinuation: CheckedContinuation<Void, Never>?

    // MARK: auth

    func isAuthenticated() async -> Bool {
        let cookies = await dataStore.httpCookieStore.allCookies()
        guard let key = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }) else { return false }
        if let exp = key.expiresDate, exp < Date() { return false }   // expired = absent
        return true
    }

    func openLogin() {
        if let w = loginWindow { w.makeKeyAndOrderFront(nil); return }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = dataStore
        let wv = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 720), configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        let win = NSWindow(contentRect: wv.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Sign in to Claude"
        win.contentView = wv
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.isReleasedWhenClosed = false
        loginWindow = win
    }

    func logout() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let claude = records.filter { $0.displayName.contains("claude.ai") || $0.displayName.contains("anthropic") }
        await dataStore.removeData(ofTypes: types, for: claude)
        resetScraper()
    }
}

extension ClaudeSession: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume(); loadContinuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(); loadContinuation = nil
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let host = navigationAction.request.url?.host else { decisionHandler(.cancel); return }
        let isLogin = (webView == loginWindow?.contentView)
        let allowed: Bool
        if isLogin {
            allowed = host.hasSuffix("claude.ai")
                || host.hasSuffix("anthropic.com")
                || host.hasSuffix("google.com")
        } else {
            allowed = host.hasSuffix("claude.ai")   // scraper: claude.ai only
        }
        decisionHandler(allowed ? .allow : .cancel)
    }

    // Deny popups (WKWebView analog of setWindowOpenHandler deny).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return nil
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ClaudeSession scraper + login with navigation guards"
```

---

## Task 8: UsagePoller

**Files:**
- Create: `ClaudeUsageBar/Session/UsagePoller.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import Combine

@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var state = UsageState()

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
        let newState = await session.fetchUsageViaDOM()
        guard !newState.isEmpty else { return }
        state = newState
        onUpdate?(newState)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add UsagePoller with restart-on-wake support"
```

---

## Task 9: GlassBackground (Liquid Glass with fallback)

**Files:**
- Create: `ClaudeUsageBar/Views/GlassBackground.swift`

- [ ] **Step 1: Implement availability-gated glass**

```swift
import SwiftUI

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: 16))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension View {
    func glassBackground() -> some View { modifier(GlassBackground()) }
}
```

If `glassEffect` is unavailable in the installed SDK, replace the `#available` branch body with `.background(.regularMaterial, in: .rect(cornerRadius: 16))` and leave a `// TODO: glassEffect on macOS 26 SDK` note. (Only adjust if it does not compile.)

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add GlassBackground with material fallback"
```

---

## Task 10: PopoverView (SwiftUI)

**Files:**
- Create: `ClaudeUsageBar/Views/PopoverView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: UsagePoller
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Usage").font(.headline)
            usageRow(title: "Current session",
                     percent: poller.state.sessionPercent,
                     subtitle: poller.state.sessionResetsIn)
            usageRow(title: "Weekly (all models)",
                     percent: poller.state.weeklyPercent,
                     subtitle: poller.state.weeklyResetsAt.map { "Resets \($0)" })
            Divider()
            HStack {
                Button("Refresh") { poller.refreshNow() }
                Spacer()
                Button("Settings…", action: onOpenSettings)
            }
        }
        .padding(20)
        .frame(width: 280)
        .glassBackground()
        .animation(.easeInOut, value: poller.state)
    }

    @ViewBuilder
    private func usageRow(title: String, percent: Int?, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(UsageFormatting.menuBarLabel(for: percent))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color(UsageFormatting.color(for: percent)))
            }
            ProgressView(value: Double(percent ?? 0), total: 100)
                .tint(Color(UsageFormatting.color(for: percent)))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add PopoverView with progress bars and glass background"
```

---

## Task 11: SettingsView (SwiftUI)

**Files:**
- Create: `ClaudeUsageBar/Views/SettingsView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore
    let session: ClaudeSession
    let launch: LaunchAtLogin
    var onIntervalChange: () -> Void

    @State private var interval: Double
    @State private var sessionThreshold: Double
    @State private var weeklyThreshold: Double
    @State private var launchEnabled: Bool
    @State private var authed = false

    init(settings: SettingsStore, session: ClaudeSession, launch: LaunchAtLogin, onIntervalChange: @escaping () -> Void) {
        self.settings = settings; self.session = session; self.launch = launch
        self.onIntervalChange = onIntervalChange
        _interval = State(initialValue: Double(settings.pollIntervalSeconds))
        _sessionThreshold = State(initialValue: Double(settings.sessionThreshold))
        _weeklyThreshold = State(initialValue: Double(settings.weeklyThreshold))
        _launchEnabled = State(initialValue: settings.launchAtLogin)
    }

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text(authed ? "Signed in" : "Not signed in")
                    Spacer()
                    Button(authed ? "Log out" : "Log in") {
                        Task {
                            if authed { await session.logout() } else { session.openLogin() }
                            authed = await session.isAuthenticated()
                        }
                    }
                }
            }
            Section("Polling") {
                Slider(value: $interval, in: 30...300, step: 10) { Text("Interval") }
                    .onChange(of: interval) { _, v in settings.pollIntervalSeconds = Int(v); onIntervalChange() }
                Text("\(Int(interval))s")
            }
            Section("Notifications") {
                Slider(value: $sessionThreshold, in: 50...100, step: 5)
                    .onChange(of: sessionThreshold) { _, v in settings.sessionThreshold = Int(v) }
                Text("Session alert at \(Int(sessionThreshold))%")
                Slider(value: $weeklyThreshold, in: 50...100, step: 5)
                    .onChange(of: weeklyThreshold) { _, v in settings.weeklyThreshold = Int(v) }
                Text("Weekly alert at \(Int(weeklyThreshold))%")
            }
            Section {
                Toggle("Launch at login", isOn: $launchEnabled)
                    .onChange(of: launchEnabled) { _, v in settings.launchAtLogin = v; launch.setEnabled(v) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 420)
        .task { authed = await session.isAuthenticated() }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add SettingsView (account, interval, thresholds, launch)"
```

---

## Task 12: LaunchAtLogin (SMAppService)

**Files:**
- Create: `ClaudeUsageBar/Services/LaunchAtLogin.swift`

- [ ] **Step 1: Implement**

```swift
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
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add LaunchAtLogin via SMAppService"
```

---

## Task 13: StatusItemController — wire button, popover, color

**Files:**
- Modify: `ClaudeUsageBar/StatusBar/StatusItemController.swift`

- [ ] **Step 1: Replace placeholder with full controller**

```swift
import AppKit
import SwiftUI

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let poller: UsagePoller
    private let makeSettings: () -> Void
    private var lastRenderedPercent: Int?

    init(poller: UsagePoller, onOpenSettings: @escaping () -> Void) {
        self.poller = poller
        self.makeSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.attributedTitle = UsageFormatting.attributedTitle(for: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(poller: poller, onOpenSettings: onOpenSettings))
    }

    func render(state: UsageState) {
        let p = state.sessionPercent
        guard p != lastRenderedPercent else { return }   // re-render only on change
        lastRenderedPercent = p
        statusItem.button?.attributedTitle = UsageFormatting.attributedTitle(for: p)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: wire StatusItemController button, popover, color render"
```

---

## Task 14: AppDelegate — wire everything + sleep/wake + settings window

**Files:**
- Modify: `ClaudeUsageBar/App/AppDelegate.swift`

- [ ] **Step 1: Full composition root**

```swift
import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let session = ClaudeSession()
    private let launch = LaunchAtLogin()
    private let notifier = Notifier()
    private lazy var poller = UsagePoller(session: session, settings: settings)
    private var statusController: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestAuthorization()

        let controller = StatusItemController(poller: poller) { [weak self] in self?.openSettings() }
        statusController = controller

        poller.onUpdate = { [weak self] state in
            guard let self else { return }
            controller.render(state: state)
            self.notifier.check(state: state, settings: self.settings)
        }
        poller.start()

        // Sleep/wake: rebuild scraper + immediate refresh.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleWake() {
        session.resetScraper()
        poller.restart()
        poller.refreshNow()
    }

    private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = SettingsView(settings: settings, session: session, launch: launch) { [weak self] in
            self?.poller.restart()
        }
        let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 420),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Claude Usage Bar Settings"
        win.contentView = NSHostingView(rootView: view)
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Build and run end-to-end**

Run: `xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar build`
Expected: BUILD SUCCEEDED. Launch from Xcode. Verify: menu-bar shows `—` then a `%` after login; clicking opens the glass popover; Settings window opens; login flow loads claude.ai.

- [ ] **Step 3: Manual smoke checklist**

- [ ] Log in via Settings → menu bar shows a session % within ~12s.
- [ ] Color shifts to orange/red at high % (can fake by editing `tier` thresholds temporarily).
- [ ] Sleep the Mac, wake it → % refreshes without re-login.
- [ ] Quit and relaunch → still signed in (persistent data store).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: compose app, sleep/wake recovery, settings window"
```

---

## Task 15: README + unsigned-run instructions

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

Include: what it is (unofficial, not affiliated with Anthropic), how it works (scrapes `claude.ai/settings/usage` with the user's own session, no telemetry, nothing sent anywhere except claude.ai), build instructions (`xcodebuild` / open in Xcode), and the unsigned-app run note:

```markdown
## Running the unsigned build

This app is not code-signed (no Apple Developer account yet). After copying
`ClaudeUsageBar.app` to /Applications, clear the quarantine flag:

    xattr -cr /Applications/ClaudeUsageBar.app

Then open it normally.
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "docs: add README with unsigned-run instructions"
```

---

## Self-Review notes

- **Spec coverage:** status item (T1,T13) · UsageState (T2) · WKWebView scrape + login + nav guards + popup deny + sessionKey expiry check (T7) · parser regex port (T3) · poller + min interval + wake restart (T8,T14) · SettingsStore + key validation via clamping (T4) · launch-at-login SMAppService (T12) · threshold notifications (T6,T14) · styled menu-bar text + color tiers (T5,T13) · Liquid Glass popover + fallback (T9,T10) · settings UI (T11) · sleep/wake recovery + persistent cookies (T7,T8,T14) · README/xattr (T15). All spec sections mapped.
- **Type consistency:** `UsageState` fields, `UsageFormatting.attributedTitle/color/tier`, `ThresholdTracker.evaluate`, `Notifier.check`, `UsagePoller.restart/refreshNow/onUpdate`, `ClaudeSession.fetchUsageViaDOM/resetScraper/openLogin/logout/isAuthenticated`, `LaunchAtLogin.setEnabled` — names consistent across tasks.
- **Known fragility:** parser regexes mirror current page text; update + version-bump when Anthropic redesigns `/settings/usage`.
- **Test caveat:** `xcodebuild test` requires the test target wired in Task 1; pure-logic tests (T3–T6) run without a signed build. UI/web tasks are build + manual smoke (T14).
```
