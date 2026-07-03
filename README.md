# Claude Usage Bar

A native macOS menu-bar app that shows your real-time Claude usage — current
**session %** and **weekly %** — by reading `claude.ai/settings/usage` with your
own logged-in session.

> **Unofficial.** Not affiliated with Anthropic. No telemetry: nothing is sent
> anywhere except `claude.ai`, using your own WebKit session. Your `sessionKey`
> cookie is never logged or written to disk by this app — it lives only in the
> system WebKit data store.

---

## Features

- **Menu-bar glyph** — percentage text with a small progress bar beneath, drawn
  as a template image so it adapts to light/dark menu bars. Shows a sign-in
  glyph when you're logged out.
- **Liquid Glass panel** (macOS 26+) — a borderless, fade-in/out panel with
  session and weekly progress rings, reset times, and your plan. Rings animate
  with spring physics; the number rolls on update. Falls back to a translucent
  material on macOS 14–15.
- **Signed-out state** — clear "Not signed in" prompt with a **Sign in** button
  when there's no valid session.
- **Threshold notifications** — native alerts when session or weekly usage
  crosses a level you set (no duplicate spam).
- **Launch at login** via `SMAppService`.
- **Keyboard & mouse** — ⌘R refresh, ⌘, settings while the panel is open;
  right-click the menu-bar icon for **Settings** / **Quit**.
- **Sleep/wake recovery** — rebuilds the scraper and refreshes on wake.
- Respects **Reduce Motion**.

## Requirements

- **Runtime:** macOS 14 or later (Liquid Glass on macOS 26+).
- **Build:** Xcode with the **macOS 26 SDK** — `.glassEffect` /
  `GlassEffectContainer` only compile against that SDK.

## Install

### Download a release

Grab the latest `ClaudeUsageBar.dmg` from the **Releases** page, open it, and
drag `ClaudeUsageBar.app` onto the **Applications** folder.

The build is **ad-hoc signed and not notarized** (no Apple Developer Program
account). Ad-hoc signing of the full bundle is required for usage
notifications to work — Notification Center refuses unsigned apps. Clear the
quarantine flag once:

```bash
xattr -cr /Applications/ClaudeUsageBar.app
```

Then open it normally. It runs as a menu-bar agent (no Dock icon).

### Build from source

```bash
xcodebuild -project ClaudeUsageBar/ClaudeUsageBar.xcodeproj \
  -scheme ClaudeUsageBar -configuration Release build
```

Or open `ClaudeUsageBar/ClaudeUsageBar.xcodeproj` in Xcode and Run.

## Usage

1. Click the menu-bar icon → **Sign in** (or **Settings → Log in**).
2. Sign in to Claude in the window that appears. It closes automatically the
   moment a valid session cookie exists, and usage appears within a few seconds.
3. The icon shows your session %; click it any time for the full panel.

> **Passkey / device-key sign-in is unavailable.** WKWebView passkeys require the
> `com.apple.developer.web-browser.public-key-credential` entitlement, which Apple
> only grants to **paid** developer teams. Use email, password, or Google sign-in.

## How it works

A hidden `WKWebView` loads `claude.ai/settings/usage` on a timer (default 60s,
min 30s), reads the rendered page text, and parses the session/weekly
percentages with regexes that mirror the page layout. A persistent
`WKWebsiteDataStore` keeps you logged in across launches and wake. Only one fetch
runs at a time.

**Parser fragility:** the regexes in `Session/UsageParser.swift` mirror the
visible text of `/settings/usage` ("Current session", "All models",
"Resets in …"). When Anthropic redesigns that page, update the regexes.

## Privacy & security

- **No telemetry, no analytics, no servers.** The app only talks to `claude.ai`.
- The **scraper** WebView blocks navigation to any origin outside `claude.ai`.
- The **sign-in** WebView allows the full OAuth flow (Claude + providers such as
  Google) and opens OAuth popups in their own window so sign-in completes.
- A desktop Safari user-agent is used so providers don't reject the embedded
  webview.
- `sessionKey` is never logged or persisted to disk by this app — it stays in the
  system WebKit data store.

## Releases (CI)

`.github/workflows/release.yml` builds the app and publishes a GitHub Release
(`v1.0.<run-number>`, unsigned `.dmg`) on every push to `main`/`master`. The
runner needs the macOS 26 SDK (`macos-26`); switch to `macos-latest` if
unavailable.

## License

See `LICENSE` if present. Unofficial tool — use at your own risk.
