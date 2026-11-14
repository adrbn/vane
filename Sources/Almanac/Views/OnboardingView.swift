#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// First launch: welcome, a guided App Store Connect key, then what arrives when.
/// Fills the left of the window while the demo app runs on the right; `onboarded` remembers it.
struct OnboardingView: View, SettingsBlocks {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.blocks.id
    @State private var step = 0
    @State private var connected = Keychain.credentials().isComplete
    @State private var showingQR = false

    // One scale, shared with the iPhone welcome: 8 / 16 / 24 / 32 / 48 spacing, text 28 / 15 / 13.
    var body: some View {
        let t = AlmanacTheme.named(themeId)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= step ? t.accent : t.sep2).frame(width: i == step ? 24 : 8, height: 6)
                }
                Spacer()
                Text("Step \(step + 1) of 3").font(t.font(13)).foregroundStyle(t.label2)
            }
            .padding(.bottom, 32)
            ScrollView { page(t).frame(maxWidth: .infinity, alignment: .leading) }
                .scrollIndicators(.never)
            footer(t).padding(.top, 24)
        }
        .padding(.horizontal, 40).padding(.top, 64).padding(.bottom, 32)
        .foregroundStyle(t.label)
        .font(t.font(13))
        .tint(t.accent)
        .animation(.easeOut(duration: 0.2), value: step)
        .sheet(isPresented: $showingQR) { SetupQR(url: SetupLink.url(for: Keychain.credentials())) }
    }

    @ViewBuilder private func page(_ t: AlmanacTheme) -> some View {
        switch step {
        case 0: welcome(t)
        case 1: connect(t)
        default: next(t)
        }
    }

    // MARK: 1. Welcome

    private func welcome(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).padding(-4)
                heading(t, String(localized: "Welcome to Vane"), String(localized: "Your App Store Connect numbers, on your Mac. It reads Apple's reports and tells you what changed."))
            }
            VStack(alignment: .leading, spacing: 24) {
                feature(t, "lightbulb.fill", .insights, String(localized: "Insights"), String(localized: "Milestones, drops and keyword issues, spotted for you."))
                feature(t, "chart.xyaxis.line", .appstore, String(localized: "Every metric"), String(localized: "Impressions, conversion, downloads, sales and sessions."))
                feature(t, "text.bubble.fill", .reviews, String(localized: "Listing and reviews"), String(localized: "Edit your metadata and answer reviews in one place."))
            }
            Text("Setup takes about five minutes: you create an API key in App Store Connect and add it here. Or look around with demo apps first.")
                .font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(_ t: AlmanacTheme, _ symbol: String, _ section: AlmanacTheme.Section, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            IconSquare(symbol: symbol, style: t.square(section), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(t.font(15, .semibold))
                Text(text).font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 2. Connect

    private func connect(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(t, String(localized: "Connect App Store Connect"), String(localized: "Vane reads your reports with an API key. The key stays in your Keychain and never leaves this Mac."))
            group(t, "") {
                guide(t, 1, String(localized: "Create a key"), String(localized: "Users and Access → Integrations → App Store Connect API. Give it the Sales and Reports role."),
                      link: (String(localized: "Open"), "https://appstoreconnect.apple.com/access/integrations/api"))
                guide(t, 2, String(localized: "Download the .p8 and drop it below"), String(localized: "Apple lets you download it only once. Vane reads the Key ID from the file name; copy the Issuer ID shown above the keys."))
                guide(t, 3, String(localized: "Find your vendor number"), String(localized: "Payments and Financial Reports, at the top left of the page."),
                      link: (String(localized: "Open"), "https://appstoreconnect.apple.com/itc/payments_and_financial_reports"))
            }
            ConnectForm(caption: nil) { connected = true; step = 2 }
        }
    }

    private func guide(_ t: AlmanacTheme, _ n: Int, _ title: String, _ text: String, link: (String, String)? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(t.font(11, .bold)).foregroundStyle(t.accent)
                .frame(width: 20, height: 20).background(t.accentSoft, in: Circle())
                .padding(.top, 10)
            row(t, title, text) {
                if let link, let url = URL(string: link.1) {
                    SmallButton(label: link.0, symbol: "arrow.up.right") { NSWorkspace.shared.open(url) }
                }
            }
            .padding(.leading, -12)
        }
        .padding(.leading, 12)
    }

    // MARK: 3. What happens next

    private func next(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(t, connected ? String(localized: "Here's what happens next") : String(localized: "Look around first"),
                    connected ? String(localized: "Apple doesn't send everything at once. Vane fills in as each report arrives.")
                              : String(localized: "You're looking at demo apps. Connect your key in Settings → App Store Connect whenever you're ready."))
            group(t, "") {
                timeline(t, String(localized: "Sales history"), connected ? String(localized: "Now. Downloads, proceeds and territories, as far back as Apple keeps them.") : String(localized: "Right after you connect."),
                         state: !connected ? .waiting : model.syncing ? .working : .done)
                timeline(t, String(localized: "Apple's analytics"), String(localized: "In 1 to 2 days. Impressions, page views, conversion and sessions, as Apple publishes each report."), state: .waiting)
                timeline(t, String(localized: "Insights"), String(localized: "As soon as there's something to say: milestones, drops, keyword issues."), state: .waiting)
            }
            if connected {
                group(t, "") {
                    row(t, String(localized: "Vane on iPhone"), String(localized: "Scan a code with the iPhone app to use the same key there.")) {
                        SmallButton(label: String(localized: "Show Code…")) { showingQR = true }
                    }
                }
            }
            RefreshSettings(title: String(localized: "Stay up to date"))
        }
    }

    private enum State { case done, working, waiting }

    private func timeline(_ t: AlmanacTheme, _ title: String, _ text: String, state: State) -> some View {
        row(t, title, text) {
            switch state {
            case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(t.pos)
            case .working: Spinner().frame(width: 14, height: 14)
            case .waiting: Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(t.label3)
            }
        }
    }

    // MARK: Chrome

    private func heading(_ t: AlmanacTheme, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(t.font(28, .bold)).tracking(-0.3).fixedSize(horizontal: false, vertical: true)
            Text(text).font(t.font(15)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footer(_ t: AlmanacTheme) -> some View {
        HStack(spacing: 8) {
            if step > 0 { OnboardingButton(label: String(localized: "Back")) { step -= 1 } }
            Spacer()
            switch step {
            case 0:
                OnboardingButton(label: String(localized: "Look Around with Demo Data")) { finish() }
                OnboardingButton(label: String(localized: "Continue"), prominent: true) { step = 1 }.keyboardShortcut(.defaultAction)
            case 1:
                OnboardingButton(label: connected ? String(localized: "Continue") : String(localized: "Skip for Now"), prominent: connected) { step = 2 }
            default:
                OnboardingButton(label: connected ? String(localized: "Open Vane") : String(localized: "Start"), prominent: true) { finish() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        model.onboardingOpen = false
    }
}
/// The onboarding's buttons: one height and font for all, larger than the app's small buttons.
private struct OnboardingButton: View {
    @Environment(\.theme) private var t
    var label: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(t.font(14, .semibold)).lineLimit(1)
                .foregroundStyle(prominent ? t.onAccent : t.label)
                .padding(.horizontal, 16).frame(height: 36)
                .background(prominent ? t.accent : t.card, in: RoundedRectangle(cornerRadius: t.rS + 2, style: .continuous))
                .overlay { if !prominent { RoundedRectangle(cornerRadius: t.rS + 2, style: .continuous).strokeBorder(t.sep2, lineWidth: 1) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The real app, drawn at 60 % in a rounded frame: what Vane looks like while you set it up. Not clickable.
struct OnboardingPreview<Content: View>: View {
    @Environment(\.theme) private var t
    @ViewBuilder var content: Content
    /// The app is drawn at its default window size, then scaled down whole, so tiles keep their real proportions.
    private let canvas = CGSize(width: 1240, height: 800)
    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 80
            let s = w / canvas.width
            ZStack(alignment: .topLeading) {
                ThemeBackground()
                content.padding(.top, 28)
            }
            .frame(width: canvas.width, height: canvas.height)
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: w, height: canvas.height * s, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: t.r * 0.7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.r * 0.7, style: .continuous).strokeBorder(t.sep2, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 30, y: 12)
            .frame(width: g.size.width, height: g.size.height)
        }
        .background(t.fill.ignoresSafeArea())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
