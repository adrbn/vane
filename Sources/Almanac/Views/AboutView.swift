import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// About: the icon, the version, then three links (source, Ko-fi, issues). Same cards and buttons as Settings, in every look.
struct AboutView: View {
    @Environment(\.theme) private var t
    @Environment(\.openURL) private var openURL

    static let repo = URL(string: "https://github.com/adrbn/vane")!
    static let kofi = URL(string: "https://ko-fi.com/adrbn")!
    static let issues = URL(string: "https://github.com/adrbn/vane/issues/new")!

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                VaneIcon(size: 88)
                Text("Vane").font(t.font(26, .heavy)).tracking(-0.5)
                Text("Version \(Self.version)").font(t.font(12, .semibold)).foregroundStyle(t.label2).monospacedDigit()
                Text("Your App Store Connect numbers, read for you.")
                    .font(t.font(14)).foregroundStyle(t.label2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            VStack(spacing: 0) {
                link(symbol: "chevron.left.forwardslash.chevron.right", section: .appstore, title: String(localized: "Source code"),
                     detail: "github.com/adrbn/vane", button: String(localized: "Open"), url: Self.repo)
                t.sep.frame(height: 1).padding(.leading, 56)
                link(symbol: "cup.and.saucer.fill", section: .insights, title: String(localized: "Support Vane"),
                     detail: String(localized: "Vane is free. A coffee on Ko-fi keeps it going."), button: "Ko-fi", url: Self.kofi, prominent: true)
                t.sep.frame(height: 1).padding(.leading, 56)
                link(symbol: "exclamationmark.bubble", section: .reviews, title: String(localized: "Report a problem"),
                     detail: String(localized: "Or suggest a feature on GitHub."), button: String(localized: "New Issue"), url: Self.issues)
            }
            .themedCard(padding: 0, radius: t.rS + 2)

            Text("Free and open source under the MIT license. Made by adrbn.\nNot affiliated with Apple.")
                .font(t.font(11)).foregroundStyle(t.label3).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func link(symbol: String, section: AlmanacTheme.Section, title: String, detail: String, button: String, url: URL, prominent: Bool = false) -> some View {
        HStack(spacing: 12) {
            IconSquare(symbol: symbol, style: t.square(section), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(t.font(13, .semibold))
                Text(detail).font(t.font(11)).foregroundStyle(t.label2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            SmallButton(label: button, prominent: prominent) { openURL(url) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 56)
    }

    static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "–"
        let b = i?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }
}

/// The app's own icon, as the system renders it.
struct VaneIcon: View {
    var size: CGFloat
    var body: some View {
        #if os(macOS)
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: size, height: size)
        #else
        // iOS can't read its own Icon Composer icon back, so a 256 px render ships beside it (ictool, see HANDOFF_NOTES).
        Image(uiImage: UIImage(named: "AboutIcon") ?? UIImage()).resizable().frame(width: size, height: size)
        #endif
    }
}
