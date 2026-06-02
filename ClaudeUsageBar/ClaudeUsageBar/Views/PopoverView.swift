import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: UsagePoller
    var onOpenSettings: () -> Void
    var onSignIn: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    private var updatedString: String {
        guard let at = poller.state.scrapedAt else { return "Not updated yet" }
        return "Updated \(Self.timeFormatter.string(from: at))"
    }

    private var stateAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CLAUDE USAGE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                if let plan = poller.state.plan, !poller.state.signedOut {
                    Text(plan)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if poller.state.signedOut {
                signedOutContent
            } else {
                usageContent
            }
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .glassBackground(cornerRadius: 22)
        .animation(stateAnimation, value: poller.state)
    }

    private var usageContent: some View {
        VStack(spacing: 0) {
            // Rings
            HStack(spacing: 16) {
                UsageRing(percent: poller.state.sessionPercent,
                          title: "SESSION",
                          subtitle: poller.state.sessionResetsIn.map { "resets in \($0)" },
                          reduceMotion: reduceMotion)
                UsageRing(percent: poller.state.weeklyPercent,
                          title: "WEEKLY",
                          subtitle: poller.state.weeklyResetsAt.map { "resets \($0)" },
                          reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)

            Divider()

            // Footer
            HStack {
                Text(updatedString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                footerButtons
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var signedOutContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 4) {
                Text("Not signed in")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Sign in to your Claude account to track usage.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            signInButton
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var signInButton: some View {
        if #available(macOS 26.0, *) {
            Button("Sign in", action: onSignIn)
                .buttonStyle(.glassProminent)
                .tint(Color(red: 0.78, green: 0.36, blue: 0.27))
        } else {
            Button("Sign in", action: onSignIn)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.36, blue: 0.27))
        }
    }

    @ViewBuilder
    private var refreshLabel: some View {
        if poller.isRefreshing {
            ProgressView().controlSize(.small)
        } else {
            Text("Refresh")
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Settings", action: onOpenSettings)
                        .buttonStyle(.glass)
                        .keyboardShortcut(",", modifiers: .command)
                    Button(action: { poller.refreshNow() }) { refreshLabel }
                        .buttonStyle(.glassProminent)
                        .tint(Color(red: 0.78, green: 0.36, blue: 0.27))
                        .disabled(poller.isRefreshing)
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        } else {
            HStack(spacing: 8) {
                Button("Settings", action: onOpenSettings)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(",", modifiers: .command)
                Button(action: { poller.refreshNow() }) { refreshLabel }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.78, green: 0.36, blue: 0.27))
                    .disabled(poller.isRefreshing)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

private struct UsageRing: View {
    let percent: Int?
    let title: String
    let subtitle: String?
    let reduceMotion: Bool

    private var ringColor: Color { Color(UsageFormatting.color(for: percent)) }
    private var trim: CGFloat { CGFloat(min(100, max(0, percent ?? 0))) / 100 }

    private var fillAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: trim)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(fillAnimation, value: trim)
                    .animation(fillAnimation, value: ringColor)
                Text(UsageFormatting.menuBarLabel(for: percent))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .frame(width: 120, height: 120)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Text(subtitle ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
