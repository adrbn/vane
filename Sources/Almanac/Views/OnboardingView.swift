#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// First launch: welcome and theme, a guided App Store Connect key, then what arrives when.
/// Shown over the demo dashboard (blurred) until finished or skipped; `onboarded` remembers it.
struct OnboardingView: View, SettingsBlocks {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.nocturne.id
    @State private var step = 0
    @State private var connected = Keychain.credentials().isComplete

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= step ? t.accent : t.sep2).frame(width: i == step ? 22 : 8, height: 6)
                }
                Spacer()
                Text("Step \(step + 1) of 3").font(t.font(11)).foregroundStyle(t.label3)
            }
            ViewThatFits(in: .vertical) {
                page(t)
                ScrollView { page(t) }.scrollIndicators(.never)
            }
            footer(t)
        }
        .foregroundStyle(t.label)
        .font(t.font(13))
        .tint(t.accent)
        .animation(.easeOut(duration: 0.2), value: step)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                heading(t, "Welcome to Vane", "Your App Store Connect numbers, on your Mac. It reads Apple's reports and tells you what changed.")
            }
            HStack(alignment: .top, spacing: 12) {
                feature(t, "lightbulb.fill", "Insights", "Milestones, drops and keyword issues, spotted for you.")
                feature(t, "chart.xyaxis.line", "Every metric", "Impressions, conversion, downloads, sales and sessions.")
                feature(t, "text.bubble.fill", "Listing and reviews", "Edit your metadata and answer reviews in one place.")
            }
            .fixedSize(horizontal: false, vertical: true)
            group(t, "Pick a look", "Change it any time in Settings.") { ThemePicker() }
        }
    }

    private func feature(_ t: AlmanacTheme, _ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.accent)
                .frame(height: 18)
            Text(title).font(t.font(13, .semibold))
            Text(text).font(t.font(11)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedCard(padding: 12, radius: t.rS + 2)
    }

    // MARK: 2. Connect

    private func connect(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(t, "Connect App Store Connect", "Vane reads your reports with an API key. The key stays in your Keychain and never leaves this Mac.")
            group(t, "") {
                guide(t, 1, "Create a key", "Users and Access → Integrations → App Store Connect API. Give it the Sales and Reports role.",
                      link: ("Open", "https://appstoreconnect.apple.com/access/integrations/api"))
                guide(t, 2, "Download the .p8", "Apple lets you download it only once. Copy the Issuer ID and Key ID shown above the keys.")
                guide(t, 3, "Find your vendor number", "Payments and Financial Reports, at the top left of the page.",
                      link: ("Open", "https://appstoreconnect.apple.com/itc/payments_and_financial_reports"))
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
        VStack(alignment: .leading, spacing: 20) {
            heading(t, connected ? "Here's what happens next" : "Look around first",
                    connected ? "Apple doesn't send everything at once. Vane fills in as each report arrives."
                              : "You're looking at demo apps. Connect your key in Settings → App Store Connect whenever you're ready.")
            group(t, "") {
                timeline(t, "Sales history", connected ? "Now. Downloads, proceeds and territories, as far back as Apple keeps them." : "Right after you connect.",
                         state: !connected ? .waiting : model.syncing ? .working : .done)
                timeline(t, "Apple's analytics", "In 1 to 2 days. Impressions, page views, conversion and sessions, as Apple publishes each report.", state: .waiting)
                timeline(t, "Insights", "As soon as there's something to say: milestones, drops, keyword issues.", state: .waiting)
            }
            RefreshSettings(title: "Stay up to date")
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(t.font(22, .bold))
            Text(text).font(t.font(13)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footer(_ t: AlmanacTheme) -> some View {
        HStack(spacing: 8) {
            if step > 0 { SmallButton(label: "Back") { step -= 1 } }
            Spacer()
            switch step {
            case 0:
                SmallButton(label: "Look Around with Demo Data") { finish() }
                SmallButton(label: "Continue", prominent: true) { step = 1 }.keyboardShortcut(.defaultAction)
            case 1:
                SmallButton(label: connected ? "Continue" : "Skip for Now", prominent: connected) { step = 2 }
            default:
                SmallButton(label: connected ? "Open Vane" : "Start", prominent: true) { finish() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        model.onboardingOpen = false
    }
}
#endif
