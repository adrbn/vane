#if os(macOS)
import AlmanacCore
import AppKit
import SwiftUI

/// Mac Settings, shown as a sheet inside the main window: themes with previews, App Store Connect, Refresh, Assistant, Data.
struct MacSettingsView: View, SettingsBlocks {
    @Environment(AppModel.self) private var model
    @AppStorage(AlmanacTheme.storageKey) private var themeId = AlmanacTheme.blocks.id
    @AppStorage("aiProvider") private var provider = Assistant.Provider.claude.rawValue
    @AppStorage("aiModel") private var aiModel = "sonnet"
    @State private var cli: String??
    @State private var tab: Tab = Keychain.credentials().isComplete ? .general : .account

    enum Tab: String, CaseIterable { case general = "General", account = "App Store Connect", assistant = "Assistant", data = "Data", about = "About"
        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .account: String(localized: "App Store Connect")
            case .assistant: String(localized: "Assistant")
            case .data: String(localized: "Data")
            case .about: String(localized: "About")
            }
        }
    }

    var body: some View {
        let t = AlmanacTheme.named(themeId)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(t.font(20, .bold))
                Spacer()
                SmallButton(label: String(localized: "Done"), prominent: true) { model.settingsOpen = false }
                    .keyboardShortcut(.cancelAction)
            }
            GlassSegments(options: Tab.allCases.map { ($0, $0.title) }, selection: $tab.animation(.easeOut(duration: 0.2)))
            // Sized to the tab's content, like Safari's or Xcode's settings: the sheet is pinned at the top
            // (see MacShell), so only its bottom edge moves. Scrolls only when the window is too short.
            ViewThatFits(in: .vertical) {
                page(t)
                ScrollView { page(t) }.scrollIndicators(.never)
            }
        }
        .foregroundStyle(t.label)
        .font(t.font(13))
        .tint(t.accent)
        .task(id: provider) { cli = nil; cli = .some(await AISettings.assistant.location()) }
        .onAppear { if model.settingsAbout { tab = .about; model.settingsAbout = false } }
        .onChange(of: model.settingsAbout) { if model.settingsAbout { tab = .about; model.settingsAbout = false } }
    }

    // MARK: Sections

    private func page(_ t: AlmanacTheme) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            switch tab {
            case .general:
                group(t, String(localized: "Appearance")) { ThemePicker() }
                group(t, String(localized: "Language")) {
                    row(t, String(localized: "Interface language"), String(localized: "Vane restarts in the new language.")) { LanguagePicker() }
                }
                RefreshSettings()
            case .account: ConnectForm()
            case .assistant: assistant(t)
            case .data: data(t)
            case .about: AboutView().environment(\.theme, t).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    private func data(_ t: AlmanacTheme) -> some View {
        group(t, "") {
            row(t, String(localized: "Stored on this Mac · \(storeSize)"), (Store.defaultPath as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                SmallButton(label: String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Store.defaultPath)]) }
            }
            if !model.isDemo {
                row(t, String(localized: "Sample data"), String(localized: "Opens a second Vane with demo apps and every metric filled in. Your data isn't touched.")) {
                    SmallButton(label: String(localized: "Open Demo Window")) {
                        let config = NSWorkspace.OpenConfiguration()
                        config.createsNewApplicationInstance = true
                        config.arguments = ["--demo"]
                        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
                    }
                }
            }
        }
    }

    private func assistant(_ t: AlmanacTheme) -> some View {
        let p = Assistant.Provider(rawValue: provider) ?? .claude
        let found: String = switch cli {
        case .none: String(localized: "Looking for \(p.rawValue)…")
        case .some(.none): String(localized: "\(p.title) isn't in your shell's PATH")
        case .some(.some(let path)): String(localized: "\(p.title) at \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
        }
        return group(t, "", nil, footer: String(localized: "Raw reports and your private key never leave this Mac. The assistant runs your own command-line tool and only sees the numbers on the screen you ask about.")) {
            row(t, String(localized: "Provider"), found, warn: cli == .some(nil)) {
                GlassSegments(options: Assistant.Provider.allCases.map { ($0.rawValue, $0 == .claude ? "Claude" : "Codex CLI") }, selection: $provider)
            }
            if p == .claude {
                row(t, String(localized: "Model"), String(localized: "sonnet, opus or haiku")) { input(t, $aiModel, "sonnet", width: 140) }
            }
        }
    }

    private var storeSize: String {
        let dir = (Store.defaultPath as NSString).deletingLastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let bytes = files.compactMap { try? FileManager.default.attributesOfItem(atPath: dir + "/" + $0)[.size] as? Int64 }.reduce(0, +)
        return bytes.formatted(.byteCount(style: .file).locale(Locale.current))
    }

}
#endif
