import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// About: the icon, the version, then Ko-fi and GitHub pills, like the README's, and the issue link. Same cards and buttons as Settings, in every look.
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

            HStack(spacing: 10) {
                Pill(symbol: "cup.and.saucer.fill", title: String(localized: "Buy me a coffee"), detail: String(localized: "Support Vane on Ko-fi"),
                     fill: Color(red: 1, green: 0.369, blue: 0.357), ink: .white) { openURL(Self.kofi) }
                Pill(symbol: "chevron.left.forwardslash.chevron.right", title: String(localized: "View on GitHub"), detail: String(localized: "Source code, MIT"),
                     fill: Color(white: 0.07), ink: .white) { openURL(Self.repo) }
            }

            VStack(spacing: 0) {
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

/// A capsule like the README buttons: icon in a soft circle, two lines, a chevron.
private struct Pill: View {
    @Environment(\.theme) private var t
    let symbol: String, title: String, detail: String, fill: Color, ink: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32).background(ink.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(t.font(14, .bold)).lineLimit(1)
                    Text(detail).font(t.font(11, .medium)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).opacity(0.85)
            }
            .foregroundStyle(ink)
            .padding(.leading, 8).padding(.trailing, 16).frame(height: 48)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            .brightness(hover ? 0.05 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
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
