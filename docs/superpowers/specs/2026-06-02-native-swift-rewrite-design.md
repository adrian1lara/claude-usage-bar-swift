# Claude Usage Bar — Native Swift Rewrite Design

**Date:** 2026-06-02
**Status:** Approved (design phase)

## Goal

Rewrite the Electron menu-bar app as a native Swift/SwiftUI macOS app for
better performance and native Liquid Glass UI. Maintain feature parity with
the Electron version plus four native improvements. No telemetry; the app
talks only to claude.ai using the user's own logged-in session.

## Decisions

| Topic | Decision |
|-------|----------|
| Data source | WKWebView scrape, ported as-is from the Electron approach |
| Scope | Feature parity + 4 native extras (below) |
| Repo | New fresh repo at `~/repos/claude-usage-bar-swift`; Electron repo archived |
| Tooling | Xcode app project (`.xcodeproj`) |
| Signing | Unsigned; users run `xattr -cr` to clear quarantine (no Apple Developer account) |
| Min OS | macOS 14; Liquid Glass on macOS 26+, plain material fallback below |

## Architecture

Hybrid shell: **AppKit** owns the status item (full control of the menu-bar
button text/color/click + Space-switch handling); **SwiftUI** renders the
popover and settings via `NSHostingController` (where Liquid Glass lives).

`LSUIElement = true` — agent app, no Dock icon.

### Components

| Unit | Job | Electron equiv |
|------|-----|----------------|
| `AppDelegate` | boot, wire dependencies, register sleep/wake observers | top of `main.js` |
| `StatusItemController` | `NSStatusItem` button: `%` text, color, click toggles popover; owns `NSPopover` | tray code |
| `ClaudeSession` (actor) | hidden offscreen `WKWebView` scraper + visible login window; persistent `WKWebsiteDataStore` | `claude-session.js` |
| `UsageParser` | `NSRegularExpression` port of the page-text regexes → `UsageState` | `parseUsageText` |
| `UsagePoller` | `Timer`, 60s default / 30s min; immediate fire on wake | `setInterval` / `restartPolling` |
| `UsageState` | model: session %, weekly %, resets-in | `lastState` |
| `SettingsStore` | `UserDefaults` wrapper | `simple-store.js` |
| `LaunchAtLogin` | `SMAppService.mainApp` register/unregister | electron shim |
| `Notifier` | `UNUserNotificationCenter`, threshold-cross alerts | new |
| `PopoverView` (SwiftUI) | progress rings/bars, resets-in countdown, glass background | `popover.html/js` |
| `SettingsView` (SwiftUI) | login/logout, poll interval, launch-at-login, thresholds | `settings.html/js` |
| `GlassBackground` | `if #available(macOS 26)` glass effect, else `.ultraThinMaterial` | new |

## Data flow

1. `UsagePoller` tick (default 60s, min 30s).
2. `ClaudeSession.fetchUsageViaDOM()` loads `https://claude.ai/settings/usage`
   in one reused hidden `WKWebView` (do not recreate per poll).
3. Poll `document.body.innerText` via `evaluateJavaScript` every 500ms for up
   to 12s, running `UsageParser.parse` until `sessionPercent` is found.
4. Result → `UsageState`, published via Combine `@Published`.
5. Subscribers update: status-item text/color, `PopoverView`, `SettingsView`.
6. Menu-bar text re-rendered only when the rounded `%` changes (cache last
   rendered percent).

## Native extras

- **Styled menu-bar text:** `NSStatusItem.button` uses an `NSAttributedString`
  in SF Rounded; color shifts green → orange → red as `%` climbs. Removes the
  Electron offscreen-canvas icon-rasterize path entirely.
- **Threshold notifications:** `Notifier` compares each new state against
  user-set thresholds (default 80%, 95%) for session and weekly. Fires once
  per upward crossing; does not re-fire until the value drops below the
  threshold again.
- **Liquid Glass popover:** SwiftUI `glassEffect` on macOS 26, material
  fallback below; animated transitions on value change.
- **Native launch-at-login:** `SMAppService.mainApp.register()` /
  `.unregister()`.

## Sleep/wake recovery

- Observe `NSWorkspace.shared.notificationCenter` `didWakeNotification`.
- On wake: destroy the scraper `WKWebView` (fresh HTTP/cookie state) and tell
  `UsagePoller` to refresh immediately (clears stale timer).
- Cookies persist via a non-ephemeral `WKWebsiteDataStore` — the manual
  cookie copy/rehydrate dance from Electron is **not needed**; the system
  persists the `sessionKey` cookie across launches and wake.

## Security boundaries (ported intact)

- `WKWebView` `decidePolicyFor navigationAction`:
  - scraper: block navigation to any origin outside `https://claude.ai`.
  - login: allow `claude.ai`, `*.anthropic.com`, `*.google.com` (Google
    OAuth); block everything else.
- No network calls to anywhere except claude.ai. No telemetry.
- `sessionKey` cookie never logged, never written to any file — lives only in
  the system `WKWebsiteDataStore`.
- `WKUIDelegate createWebViewWith` returns `nil` (deny popup windows), the
  WKWebView analog of Electron's `setWindowOpenHandler({ action: 'deny' })`.
- Settings writes validated: only known keys
  (`pollIntervalSeconds`, `launchAtLogin`, threshold values) accepted.

## File layout

```
ClaudeUsageBar.xcodeproj
ClaudeUsageBar/
  AppDelegate.swift
  StatusItemController.swift
  Session/
    ClaudeSession.swift
    UsageParser.swift
    UsagePoller.swift
  Model/
    UsageState.swift
    SettingsStore.swift
  Services/
    LaunchAtLogin.swift
    Notifier.swift
  Views/
    PopoverView.swift
    SettingsView.swift
    GlassBackground.swift
  Info.plist          (LSUIElement = true)
  Assets.xcassets
README.md             (xattr -cr unquarantine instructions)
```

## Out of scope / YAGNI

- No bundler, no codegen — direct Swift sources only.
- No Windows port (the Electron app's Windows path is dropped; macOS-native).
- No Apple notarization until a Developer account exists.

## Parser fragility note

`UsageParser` regexes mirror the visible text of `/settings/usage`
("Current session", "All models", "Resets in …"). When Anthropic redesigns
that page this breaks; update the regex set and bump the app version.
